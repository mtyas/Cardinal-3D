// SPDX-License-Identifier: GPL-3.0-or-later
#include "../bridge/Transport.hpp"
#include <cassert>
#include <iostream>
#include <thread>
#include <atomic>

using cardinal3d::Transport;
static std::vector<uint8_t> frame(const std::string& text) {
    std::vector<uint8_t> result;
    uint32_t length = text.size()+1;
    for (int i=0; i<4; ++i) result.push_back((length >> (8*i)) & 255);
    result.push_back(1); result.insert(result.end(), text.begin(), text.end()); return result;
}
int main() {
    Transport server;
    const auto seed = static_cast<uint64_t>(std::chrono::steady_clock::now().time_since_epoch().count());
    uint16_t port = 0;
    bool listening = false;
    // Hosted Windows machines reserve blocks of ports for other services.
    // Spread attempts over unprivileged ports rather than treating a collision
    // on the first random choice as a broken transport.
    for (uint64_t attempt = 0; attempt < 100 && !listening; ++attempt) {
        port = static_cast<uint16_t>(1024 + (seed + attempt * 7919) % 62000);
        listening = server.listenOn(port);
    }
    assert(listening);
    auto peer = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in address{}; address.sin_family = AF_INET; address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(connect(peer, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0);
    bool accepted = false;
    for (int i=0; i<1000 && !accepted; ++i) {
        accepted = server.acceptClient();
        if (!accepted) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(accepted);
    auto a = frame("{\"op\":\"hello\"}");
    assert(send(peer, reinterpret_cast<const char*>(a.data()), 3, 0) == 3);
    assert(server.receive().empty());
    auto b = frame("{\"op\":\"release\"}");
    a.insert(a.end(), b.begin(), b.end());
    assert(send(peer, reinterpret_cast<const char*>(a.data()+3), static_cast<int>(a.size()-3), 0) == static_cast<int>(a.size()-3));
    std::vector<std::string> commands;
    for (int i=0; i<1000 && commands.size()<2; ++i) {
        auto next = server.receive(); commands.insert(commands.end(), next.begin(), next.end());
        if (commands.size()<2) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(commands.size() == 2 && commands[1] == "{\"op\":\"release\"}");
    assert(server.json("old", "snapshot"));
    assert(server.json("ack"));
    assert(server.json("new", "snapshot"));
    server.flush();
    uint8_t output[64]; auto count = recv(peer, reinterpret_cast<char*>(output), 16, MSG_WAITALL);
    assert(count == 16); // two 3-byte messages, each with a 5-byte frame header
    assert(std::string(reinterpret_cast<char*>(output+5), 3) == "ack");
    assert(std::string(reinterpret_cast<char*>(output+13), 3) == "new");
    assert(server.queue(2, {'a', 'r', 't'}, "surface/1"));
    assert(server.json("hot", "snapshot"));
    server.flush();
    count = recv(peer, reinterpret_cast<char*>(output), 16, MSG_WAITALL);
    assert(count == 16 && output[4] == 1 && output[12] == 2);
    assert(std::string(reinterpret_cast<char*>(output+5), 3) == "hot");
    // Priority may reorder unsent frames, but must never splice metadata into
    // a surface already on the wire, even when the flush budget splits it.
    std::vector<uint8_t> pixels(5 * 1024 * 1024, 0x5a);
    assert(server.queue(2, pixels, "surface/large"));
    server.flush();
    assert(server.json("now", "snapshot"));
    std::vector<uint8_t> burst(pixels.size() + 5 + 8);
    std::atomic<bool> received{false};
    std::thread reader([&] {
        size_t offset = 0;
        while (offset < burst.size()) {
            auto n = recv(peer, reinterpret_cast<char*>(burst.data() + offset), static_cast<int>(burst.size() - offset), 0);
            assert(n > 0); offset += n;
        }
        received = true;
    });
    for (int i = 0; i < 2500 && !received; ++i) {
        server.flush(); std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(received); reader.join();
    assert(burst[4] == 2 && std::equal(pixels.begin(), pixels.end(), burst.begin() + 5));
    assert(burst[pixels.size() + 9] == 1);
    assert(std::string(reinterpret_cast<char*>(burst.data() + pixels.size() + 10), 3) == "now");
    uint8_t invalid[] = {0xff,0xff,0xff,0x7f};
    send(peer, reinterpret_cast<const char*>(invalid), sizeof(invalid), 0);
    for (int i=0; i<1000 && server.connected(); ++i) {
        server.receive(); std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(!server.connected() && server.disconnected);
    cardinal3d::net::close(peer);
    std::cout << "PASS: fragmented and coalesced frames, latest snapshots, reliable replies, malformed length disconnect\n";
}
