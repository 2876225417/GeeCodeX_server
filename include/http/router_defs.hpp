

#ifndef ROUTER_DEFS_HPP
#define ROUTER_DEFS_HPP

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

#include <initializer_list>
#include <magic_enum.hpp>
#include <map>
#include <memory>
#include <string_view>
#include <functional>

namespace geecodex::http {
    class http_connection;

    enum class http_method {
        GET,
        POST,
        PUT,
        DELETE,
        UNKNOWN
    };

    [[nodiscard]] constexpr http_method enum2method(boost::beast::http::verb method) {
        switch (method) {
            case boost::beast::http::verb::get:       return http_method::GET;
            case boost::beast::http::verb::post:      return http_method::POST;
            case boost::beast::http::verb::put:       return http_method::PUT;
            case boost::beast::http::verb::delete_:   return http_method::DELETE;
            default:                                  return http_method::UNKNOWN;
        }
    }

    [[nodiscard]] constexpr std::string_view method2string(http_method m) {
        switch(m) {
            case http_method::GET:      return "GET";
            case http_method::POST:     return "POST";
            case http_method::PUT:      return "PUT";
            case http_method::DELETE:   return "DELETE";
            case http_method::UNKNOWN:  return "UNKNOWN METHOD";
        }
    }

    enum class api_route {
        HELLO,
        HEALTH_CHECK,
        
        DOWNLOAD_PDF,
        
        FETCH_ALL_PDF_INFO,
        FETCH_PDF_COVER,
        FETCH_LATEST_BOOKS,

        APP_UPDATE_CHECK,
        APP_DOWNLOAD_LATEST,
        
        CLIENT_FEEDBACK,
        AI_CHAT,
        
        COMMENT_BOOK,
        SCORE_BOOK,
        
        CONTENT_RECOGNIZE,
        UNKNOWN
    };

    [[nodiscard]] inline std::string_view
    api2string(api_route r) {
        if (r == api_route::UNKNOWN) return "UNKNOWN";
        auto name = magic_enum::enum_name(r);
        if (name.empty()) return "Error: Invalid api_route";
        return name;    
    }

    enum class route_match_type { EXACT, PREFIX };

    struct route_info {
        std::string_view path;
        http_method method;
        api_route route;
        route_match_type match_type{route_match_type::EXACT};
    };

    using route_handler_func = std::function<void(http_connection&)>;
}   // GEECODEX::HTTP
#endif // ROUTER_DEFS_HPP