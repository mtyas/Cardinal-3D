// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <unistd.h>
#endif
#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <deque>
#include <string>
#include <vector>

namespace cardinal3d {
namespace net {
#ifdef _WIN32
using Socket = SOCKET;
static constexpr Socket invalid = INVALID_SOCKET;
inline void close(Socket fd) { ::closesocket(fd); }
inline bool nonblock(Socket fd) { u_long mode = 1; return ::ioctlsocket(fd, FIONBIO, &mode) == 0; }
inline bool wouldBlock() { return ::WSAGetLastError() == WSAEWOULDBLOCK; }
inline bool interrupted() { return ::WSAGetLastError() == WSAEINTR; }
#else
using Socket = int;
static constexpr Socket invalid = -1;
inline void close(Socket fd) { ::close(fd); }
inline bool nonblock(Socket fd) { return ::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK) == 0; }
inline bool wouldBlock() { return errno == EAGAIN || errno == EWOULDBLOCK; }
inline bool interrupted() { return errno == EINTR; }
#endif
}
// UI-thread-only, nonblocking transport. Frames: uint32 LE length, byte kind, payload.
// No socket, allocation, serialization or rendering work runs in the audio callback.
class Transport {
    net::Socket listener = net::invalid, client = net::invalid;
#ifdef _WIN32
    bool winsockReady = false;
#endif
    std::vector<uint8_t> input;
    struct Frame { std::string key; std::vector<uint8_t> bytes; size_t offset = 0; };
    std::deque<Frame> output;
    size_t queued = 0;
    static constexpr size_t limit = 24 * 1024 * 1024;
public:
    bool disconnected = false;
    Transport() = default;
    Transport(const Transport&) = delete;
    Transport& operator=(const Transport&) = delete;
    ~Transport() {
        closeClient();
        if (listener != net::invalid) net::close(listener);
#ifdef _WIN32
        if (winsockReady) ::WSACleanup();
#endif
    }
    bool listenOn(uint16_t port) {
        if (listener != net::invalid) return false;
#ifdef _WIN32
        if (!winsockReady) {
            WSADATA data{};
            if (::WSAStartup(MAKEWORD(2, 2), &data) != 0) return false;
            winsockReady = true;
        }
#endif
        listener = ::socket(AF_INET, SOCK_STREAM, 0);
        if (listener == net::invalid) return false;
        int yes = 1;
        #ifdef _WIN32
        // Do not let another process share this authenticated local endpoint.
        setsockopt(listener, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<const char*>(&yes), sizeof(yes));
#else
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
#endif
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = htons(port);
        if (::bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) || ::listen(listener, 1)) {
            net::close(listener); listener = net::invalid; return false;
        }
        if (!net::nonblock(listener)) { net::close(listener); listener = net::invalid; return false; }
        return true;
    }
    bool connected() const { return client != net::invalid; }
    void closeClient() {
        if (client != net::invalid) { net::close(client); disconnected = true; }
        client = net::invalid; input.clear(); output.clear(); queued = 0;
    }
    bool acceptClient() {
        if (listener == net::invalid || client != net::invalid) return false;
        client = ::accept(listener, nullptr, nullptr);
        if (client == net::invalid) return false;
        if (!net::nonblock(client)) { closeClient(); return false; }
        int noDelay = 1;
        setsockopt(client, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&noDelay), sizeof(noDelay));
#ifdef SO_NOSIGPIPE
        int yes = 1; setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
        return true;
    }
    bool queue(uint8_t kind, const std::vector<uint8_t>& payload, const std::string& key = "") {
        if (!connected() || payload.size() + 5 > limit) return false;
        if (!key.empty()) {
            for (auto it = output.begin(); it != output.end();) {
                if (it->key == key && it->offset == 0) { queued -= it->bytes.size(); it = output.erase(it); }
                else ++it;
            }
        }
        if (queued + payload.size() + 5 > limit) {
            // A stalled reader cannot cause unbounded memory or lose an input release.
            closeClient(); return false;
        }
        Frame frame; frame.key = key;
        const uint32_t length = static_cast<uint32_t>(payload.size() + 1);
        for (int i = 0; i < 4; ++i) frame.bytes.push_back((length >> (8*i)) & 255);
        frame.bytes.push_back(kind);
        frame.bytes.insert(frame.bytes.end(), payload.begin(), payload.end());
        queued += frame.bytes.size();
        if (kind == 1) {
            // Metadata must not wait behind unsent artwork. Never interrupt a
            // partially transmitted frame or reorder JSON replies/snapshots.
            auto at = output.begin();
            while (at != output.end() && (at->offset != 0 || at->bytes[4] == 1)) ++at;
            output.insert(at, std::move(frame));
        } else output.push_back(std::move(frame));
        return true;
    }
    bool json(const std::string& text, const std::string& key = "") {
        return queue(1, std::vector<uint8_t>(text.begin(), text.end()), key);
    }
    void flush() {
        size_t budget = 4 * 1024 * 1024;
        while (connected() && !output.empty() && budget) {
            auto& frame = output.front();
            size_t count = std::min(budget, frame.bytes.size() - frame.offset);
            auto sent = ::send(client, reinterpret_cast<const char*>(frame.bytes.data() + frame.offset), static_cast<int>(count),
#ifdef MSG_NOSIGNAL
                                 MSG_NOSIGNAL
#else
                                 0
#endif
            );
            if (sent < 0 && net::interrupted()) continue;
            if (sent < 0 && net::wouldBlock()) break;
            if (sent <= 0) { closeClient(); break; }
            frame.offset += sent; budget -= sent;
            if (frame.offset == frame.bytes.size()) { queued -= frame.bytes.size(); output.pop_front(); }
        }
    }
    std::vector<std::string> receive() {
        std::vector<std::string> commands;
        if (!connected()) return commands;
        uint8_t buffer[16384]; size_t budget = 65536;
        while (budget) {
            auto count = ::recv(client, reinterpret_cast<char*>(buffer), static_cast<int>(std::min(sizeof(buffer), budget)), 0);
            if (count < 0 && net::interrupted()) continue;
            if (count < 0 && net::wouldBlock()) break;
            if (count <= 0) { closeClient(); return commands; }
            input.insert(input.end(), buffer, buffer + count); budget -= count;
            if (input.size() > 1024 * 1024) { closeClient(); return {}; }
        }
        size_t consumed = 0;
        while (commands.size() < 64 && input.size() - consumed >= 4) {
            uint32_t length = 0;
            for (int i = 0; i < 4; ++i) length |= uint32_t(input[consumed+i]) << (8*i);
            if (length < 1 || length > 65536) { closeClient(); return {}; }
            if (input.size() - consumed < length + 4) break;
            if (input[consumed+4] != 1) { closeClient(); return {}; }
            commands.emplace_back(reinterpret_cast<char*>(input.data()+consumed+5), length-1);
            consumed += length+4;
        }
        input.erase(input.begin(), input.begin() + consumed);
        return commands;
    }
};
}
