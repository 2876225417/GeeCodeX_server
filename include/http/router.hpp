

#ifndef ROUTER_HPP
#define ROUTER_HPP


#include <http/router_defs.hpp>
#include <http/routes_app.hpp>
#include <http/routes_books.hpp>
#include <http/routes_general.hpp>

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
#include <unordered_map>

#include <spdlog/spdlog.h>
#include <spdlog/fmt/fmt.h>

namespace geecodex::http {
namespace beast = boost::beast;
    
namespace http  = beast::http;
using tcp       = boost::asio::ip::tcp;

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
    explicit trie_router(const std::vector<route_info>& all_definitions) {
        SPDLOG_DEBUG("TrieRouter construtor: Adding {} definitions to Trie.", all_definitions.size());
        for (const auto& route_def: all_definitions) add_route(route_def);
        SPDLOG_DEBUG("TrieRouter construction complete.");
    }

    trie_router(const std::initializer_list<route_info>& definitions) {
        SPDLOG_DEBUG("TrieRouter constructor: Adding {} definitions from initializer_list to Trie.", definitions.size());
        for (const auto& route_def: definitions) add_route(route_def);
        SPDLOG_DEBUG("TrieRouter construction from initializer_list complete");
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

    
inline const trie_router& get_global_route_table() {
    static const trie_router instance = []{
        std::vector<route_info> all_definitions;
        
        SPDLOG_INFO("Loading route definitions from modules...");

        auto general_defs = get_general_route_definitions();
        all_definitions.insert(all_definitions.end(), general_defs.begin(), general_defs.end());
        SPDLOG_DEBUG("Loaded {} general route definitions.", general_defs.size());

        auto book_defs = get_book_route_definitions();
        all_definitions.insert(all_definitions.end(), book_defs.begin(), book_defs.end());
        SPDLOG_DEBUG("Loaded {} book route definitions.", book_defs.size());

        auto app_defs = get_app_route_definitions();
        all_definitions.insert(all_definitions.end(), app_defs.begin(), app_defs.end());
        SPDLOG_DEBUG("Loaded {} app route definitions.", app_defs.size());

        SPDLOG_INFO("Total {} route definitions collected. Initializing Trie router...", all_definitions.size());
        SPDLOG_INFO("Registered Routes (Path, Method, API Route Name, Match Type):");
        SPDLOG_INFO("+------------------------------------------+---------+---------------------------+----------+");
        SPDLOG_INFO("| {:<40} | {:<7} | {:<25} | {:<8} |", "Path", "Method", "API Route", "Match");
        SPDLOG_INFO("+------------------------------------------+---------+---------------------------+----------+");

        for (const auto& def : all_definitions) {
            SPDLOG_INFO("| {:<40} | {:<7} | {:<25} | {:<8} |",
                        def.path,
                        to_string(def.method),        
                        to_string(def.route),         
                        to_string(def.match_type));   
        }
        SPDLOG_INFO("+------------------------------------------+---------+---------------------------+----------+");
    
        SPDLOG_INFO("Trie router initialized.");
        return trie_router(all_definitions);
    }();

    return instance;
}
    
void handle_not_found(http_connection& conn);

inline const std::unordered_map<api_route, route_handler_func>& get_route_handlers() {
    static const std::unordered_map<api_route, route_handler_func>& handlers = []{
        std::unordered_map<api_route, route_handler_func> collected_handlers;

        SPDLOG_DEBUG("Registering route handlers...");
        register_general_handlers(collected_handlers);
        SPDLOG_DEBUG("Registered genral handlers. Current count: {}", collected_handlers.size());
        register_book_handlers(collected_handlers);
        SPDLOG_DEBUG("Registered book handlers. Current count: {}", collected_handlers.size());
        register_app_handlers(collected_handlers);
        SPDLOG_DEBUG("Registered app handlers. Current count: {}", collected_handlers.size());
        
        collected_handlers[api_route::UNKNOWN] = handle_not_found;
        SPDLOG_DEBUG("Registered UNKNOWN handler. Final handler count: ", collected_handlers.size());
        SPDLOG_INFO("Route handler map initialized with {} handlers.", collected_handlers.size());

        return collected_handlers;
    }();
    return handlers;
}

}   // NAMESPACE GEECODEX_HPP
#endif // ROUTER_HPP
