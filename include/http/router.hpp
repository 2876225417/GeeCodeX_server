

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

#include <initializer_list>
#include <magic_enum.hpp>
#include <map>
#include <memory>

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

    [[nodiscard]] constexpr http_method enum2method(http::verb method) {
        switch (method) {
            case http::verb::get:       return http_method::GET;
            case http::verb::post:      return http_method::POST;
            case http::verb::put:       return http_method::PUT;
            case http::verb::delete_:   return http_method::DELETE;
            default:                    return http_method::UNKNOWN;
        }
    }

    [[nodiscard]] constexpr std::string_view to_string(http_method m) {
        switch(m) {
            case http_method::GET:      return "GET";
            case http_method::POST:     return "POST";
            case http_method::PUT:      return "PUT";
            case http_method::DELETE:   return "DELETE";
            case http_method::UNKNOWN:  return "UNKNOWN METHOD";
        }
        return "Error: Invalid http_method";
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
    to_string(api_route r) {
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

    class trie_router {
    private:
        struct node {
            std::map<char, std::unique_ptr<node>> children;
            std::map<http_method, api_route> exact_match_routes;
            std::map<http_method, api_route> prefix_match_routes;
        } m_root;

        void add_route(const route_info& route) {
            node* current = &m_root;
            
            for (char ch: route.path) {
                if (current->children.find(ch) == current->children.end())
                    current->children[ch] = std::make_unique<node>();
                current = current->children[ch].get();
            }

            if (route.match_type == route_match_type::EXACT)
                 current->exact_match_routes[route.method] = route.route;
            else current->prefix_match_routes[route.method] = route.route;
        }
    public:
        trie_router(const std::initializer_list<route_info>& definitions) {
            for (const auto& route_def: definitions) add_route(route_def);
        }

        template <typename Range>
        explicit trie_router(const Range& definitions) {
            for (const auto& route_def: definitions) add_route(route_def);
        }

        [[nodiscard]] api_route find(std::string_view path, http_method method) const {
            const node* current_node = &m_root;
            api_route longest_prefix_match = api_route::UNKNOWN;

            if (auto it = m_root.prefix_match_routes.find(method); 
                it != m_root.prefix_match_routes.end()) longest_prefix_match = it->second;

            const node* node_at_full_path_end = &m_root;

            bool path_fully_traversed_in_trie = true;
            for (char ch: path) {
                auto child_it = current_node->children.find(ch);
                if (child_it == current_node->children.end()) {
                    path_fully_traversed_in_trie = false;
                    node_at_full_path_end = nullptr;
                    break;
                }
                current_node = child_it->second.get();
                node_at_full_path_end = current_node;

                if (auto it = current_node->prefix_match_routes.find(method); 
                    it != current_node->prefix_match_routes.end()) longest_prefix_match = it->second; 
            }

            if (path_fully_traversed_in_trie && node_at_full_path_end) 
                if (auto it = node_at_full_path_end->exact_match_routes.find(method); 
                    it != node_at_full_path_end->exact_match_routes.end()) return it->second;

            return longest_prefix_match;
        }
    };

    static constexpr route_info route_definitions[] = {
        {"/geecodex/feedback",              http_method::POST,  api_route::CLIENT_FEEDBACK },
        {"/geecodex/ai/chat",               http_method::POST,  api_route::AI_CHAT},
        {"/geecodex/hello",                 http_method::GET,   api_route::HELLO},
        {"/geecodex/health",                http_method::GET,   api_route::HEALTH_CHECK},
        // Precise match should be forward than less precise
        {"/geecodex/books/latest",          http_method::GET,   api_route::FETCH_LATEST_BOOKS},
        {"/geecodex/books/cover/",          http_method::GET,   api_route::FETCH_PDF_COVER,     route_match_type::PREFIX},
        {"/geecodex/books/",                http_method::GET,   api_route::DOWNLOAD_PDF,        route_match_type::PREFIX},
        {"/geecodex/app/update_check",      http_method::POST,  api_route::APP_UPDATE_CHECK},
        {"/geecodex/app/download/latest/",  http_method::GET,   api_route::APP_DOWNLOAD_LATEST, route_match_type::PREFIX},        
        {"/geecodex/books/comment/",        http_method::POST,  api_route::COMMENT_BOOK,        route_match_type::PREFIX},     
        {"/geecodex/books/score/",         http_method::POST,  api_route::SCORE_BOOK,          route_match_type::PREFIX},
        {"/geecodex/recoginize/",          http_method::POST,  api_route::CONTENT_RECOGNIZE},
    };
    
    inline const trie_router& get_global_route_table() {
        static const trie_router instance(route_definitions);
        return instance;
    }
    
    /* ----Route Table Parser---- */


    class http_connection;
    

    void handle_hello(http_connection& conn);
    void handle_health_check(http_connection& conn);
    void handle_download_file(http_connection& conn);
    void handle_download_pdf(http_connection& conn);
    void handle_fetch_pdf_cover(http_connection& conn);
    void handle_fetch_latest_books(http_connection& conn);
    void handle_app_update_check(http_connection& conn);
    void handle_download_latest_app(http_connection& conn);
    void handle_fetch_client_feedback(http_connection& conn);
    void handle_ai_chat(http_connection& conn);
    void handle_content_recognize(http_connection& conn);
    
    void handle_score_book(http_connection& conn);
    void handle_comment_book(http_connection& conn);
      
    void handle_not_found(http_connection& conn);

    using route_handler_func = std::function<void(http_connection&)>;
    inline const std::unordered_map<api_route, route_handler_func>& get_route_handlers() {
        static const std::unordered_map<api_route, route_handler_func> handlers = {
            {api_route::HELLO, handle_hello},
            {api_route::HEALTH_CHECK, handle_health_check},
            {api_route::DOWNLOAD_PDF, handle_download_pdf},
            {api_route::FETCH_PDF_COVER, handle_fetch_pdf_cover},
            {api_route::FETCH_LATEST_BOOKS, handle_fetch_latest_books},
            {api_route::APP_UPDATE_CHECK, handle_app_update_check},
            {api_route::APP_DOWNLOAD_LATEST, handle_download_latest_app},
            {api_route::CLIENT_FEEDBACK, handle_fetch_client_feedback},
            {api_route::AI_CHAT, handle_ai_chat},
            {api_route::SCORE_BOOK, handle_score_book},
            {api_route::COMMENT_BOOK, handle_comment_book},
            {api_route::CONTENT_RECOGNIZE, handle_content_recognize},
            {api_route::UNKNOWN, handle_not_found},
        };
        return handlers;
    }
}
#endif // ROUTER_HPP
