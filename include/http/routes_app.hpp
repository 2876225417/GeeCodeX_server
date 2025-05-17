

#ifndef ROUTES_APP_HPP
#define ROUTES_APP_HPP


#include <http/router_defs.hpp>

#include <span>
#include <array>
#include <vector>
#include <unordered_map>

namespace geecodex::http {

void handle_app_update_check(http_connection &conn);
void handle_download_latest_app(http_connection &conn);

static constexpr route_info app_route_definitions_array[] = {
    {"/geecodex/app/update_check",    http_method::POST, api_route::APP_UPDATE_CHECK},
    {"/geecodex/app/download/latest", http_method::GET,  api_route::APP_DOWNLOAD_LATEST, route_match_type::PREFIX },
};

inline std::span<const route_info> get_app_route_definitions() {
    return {app_route_definitions_array, std::size(app_route_definitions_array)};
}

inline void register_app_handlers(std::unordered_map<api_route, route_handler_func>& handlers) {
    handlers[api_route::APP_UPDATE_CHECK] = handle_app_update_check;
    handlers[api_route::APP_DOWNLOAD_LATEST] = handle_download_latest_app;
}
};  // NAMESPACE GEECODEX_HTTP

#endif // ROUTES_APP_HPP