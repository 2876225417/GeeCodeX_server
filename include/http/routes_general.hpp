
#ifndef ROUTES_GENERAL_HPP
#define ROUTES_GENERAL_HPP

#include "http/router.hpp"
#include <cstddef>
#include <http/router_defs.hpp>
#include <span>
#include <array>
#include <vector>
#include <unordered_map>

namespace geecodex::http {

void handle_hello(http_connection &conn);
void handle_health_check(http_connection &conn);
void handle_fetch_client_feedback(http_connection &conn);
void handle_ai_chat(http_connection &conn);
void handle_content_recognize(http_connection &conn);

static constexpr route_info general_route_definitions_array[] = {
    {"/geecodex/hello", http_method::GET, api_route::HELLO},
    {"/geecodex/health", http_method::GET, api_route::HEALTH_CHECK},
    {"/geecodex/feedback", http_method::POST, api_route::CLIENT_FEEDBACK},
    {"/geecodex/ai/chat", http_method::POST, api_route::AI_CHAT},
    {"/geecodex/recognize", http_method::POST, api_route::CONTENT_RECOGNIZE, route_match_type::PREFIX},
};

inline static std::span<const route_info> get_general_route_definitions() {
    return {general_route_definitions_array, std::size(general_route_definitions_array)};
}

inline void register_general_handlers(std::unordered_map<api_route, route_handler_func>& handlers) {
    handlers[api_route::HELLO] = handle_hello;
    handlers[api_route::HEALTH_CHECK] = handle_health_check;
    handlers[api_route::CLIENT_FEEDBACK] = handle_fetch_client_feedback;
    handlers[api_route::AI_CHAT] = handle_ai_chat;
    handlers[api_route::CONTENT_RECOGNIZE] = handle_content_recognize;
}

}   // NAMESPACE GEECODEX::HTTP
#endif // ROUTES_GENERAL_HPP