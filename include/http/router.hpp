

#ifndef ROUTER_HPP
#define ROUTER_HPP

#include <boost/beast/core.hpp>
#include <boost/beast/core/error.hpp>
#include <boost/beast/core/flat_buffer.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/http/field.hpp>
#include <boost/beast/http/fields_fwd.hpp>
#include <boost/beast/http/file_body_fwd.hpp>
#include <boost/beast/http/message_fwd.hpp>
#include <boost/beast/http/status.hpp>
#include <boost/beast/http/string_body_fwd.hpp>
#include <boost/beast/http/verb.hpp>
#include <boost/beast/version.hpp>
#include <boost/asio.hpp>
#include <boost/core/ignore_unused.hpp>

namespace geecodex::http {

    namespace beast = boost::beast;
    namespace http  = beast::http;
    namespace net   = boost::asio;
    using tcp       = boost::asio::ip::tcp;

    /* ----Route Table Parser---- */
    enum class http_method {
        GET,
        POST,
        PUT,
        DELETE,
        UNKNOWN
    };

    inline http_method enum2method(http::verb method) {
        switch (method) {
            case http::verb::get:       return http_method::GET;
            case http::verb::post:      return http_method::POST;
            case http::verb::put:       return http_method::PUT;
            case http::verb::delete_:   return http_method::DELETE;
            default:                    return http_method::UNKNOWN;
        }
    }
    
    enum class api_route {
        HELLO,
        HEALTH_CHECK,
        UNKNOWN
    };

    struct route_info {
        std::string_view path;
        http_method method;
        api_route route;
    };

    template <size_t N>
    struct static_route_table {
        std::array<route_info, N> routes;

        template <size_t... I>
        constexpr static_route_table(const route_info (&init)[N], std::index_sequence<I...>)
            : routes{init[I]...} {}

        constexpr static_route_table(const route_info (&init)[N])
            : static_route_table(init, std::make_index_sequence<N>{}) {}
    
        constexpr api_route find(std::string_view path, http_method method) const {
            for (const auto& route: routes) 
                if (route.path == path && route.method == method) return route.route;   
            return api_route::UNKNOWN;
        }
    };

    static constexpr route_info route_definitions[] = {
    {"/geecodex/hello",     http_method::GET,   api_route::HELLO},
    {"/geecodex/health",    http_method::GET,   api_route::HEALTH_CHECK}
    };
    static constexpr auto route_table = static_route_table(route_definitions);
    /* ----Route Table Parser---- */

    class http_connection;

    void handle_hello(http_connection& conn);
    void handle_health_check(http_connection& conn);
    void handle_not_found(http_connection& conn);

    using route_handler_func = std::function<void(http_connection&)>;
    inline const std::unordered_map<api_route, route_handler_func>& get_route_handlers() {
        static const std::unordered_map<api_route, route_handler_func> handlers = {
            {api_route::HELLO, handle_hello},
            {api_route::HEALTH_CHECK, handle_health_check},
            {api_route::UNKNOWN, handle_not_found},
        };
        return handlers;
    }



}
#endif // ROUTER_HPP
