

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
#include <regex>
#include <string>
#include <string_view>
#include <type_traits>
#include <unordered_map>

#include <spdlog/spdlog.h>
#include <spdlog/fmt/fmt.h>
#include <vector>

namespace geecodex::http {
namespace beast = boost::beast;
    
namespace http  = beast::http;
using tcp       = boost::asio::ip::tcp;

class trie_router {
public:
    struct match_result {
        api_route route = api_route::UNKNOWN;
        std::map<std::string, std::string> params;
    };

private:
    struct node {
        std::map<std::string, std::unique_ptr<node>> children;
        
        std::unique_ptr<node> param_child;
        std::string param_name;

        std::unique_ptr<node> wildcard_child;
        std::string wildcard_name;

        std::map<http_method, api_route> handlers;
    } m_root;

    static std::vector<std::string_view> split_path(std::string_view path) {
        std::vector<std::string_view> segments;
        if (path.empty() || path == "/") return segments;
        
        size_t start = (path.front() == '/') ? 1 : 0;
        size_t end   = start;

        while (start < path.length()) {
            end = path.find('/', start);
            if (end == std::string_view::npos) {
                segments.push_back(path.substr(start));
                break;
            }
            segments.push_back(path.substr(start, end - start));
            start = end + 1;
        }
        return segments;
    }

    void add_route(const route_info& route) {
        node* current = &m_root;
        auto segments = split_path(route.path);
        
        for (const auto& segment: segments) {
            if (segment.empty()) continue;

            if (segment.front() == ':') {
                if (segment.length() < 2) {
                    SPDLOG_ERROR("Invalid route parameter in path: {}", route.path);
                    return;
                }
                if (current->param_child == nullptr) {
                    current->param_child->param_name = std::string(segment.substr(1));
                }
                current->param_child->param_name = std::string(segment.substr(1));
                current = current->param_child.get();
            } else if (segment.front() == '*') {
                if (segment.length() < 2) {
                    SPDLOG_ERROR("Invalid wildcard parameter in path: {}", route.path);
                    return;
                }
                if (current->wildcard_child == nullptr) {
                    current->wildcard_child = std::make_unique<node>();
                }
                current->wildcard_child->wildcard_name = std::string(segment.substr(1));
                current = current->wildcard_child.get();
                break;
            } else {
                auto& child_node = current->children[std::string(segment)];
                if (child_node == nullptr) 
                    child_node = std::make_unique<node>();
                current = child_node.get();
            }
        }
    
        if (route.match_type == route_match_type::PREFIX) {
            SPDLOG_WARN("PREFIX match_type is not fully supported with dynamic routing and is treated as EXACT for path structure: {}", route.path);
        }
        current->handlers[route.method] = route.route;
    }

    bool find_recursive(const node* current, const std::vector<std::string_view> segments, size_t depth, match_result& result) const {
        if (depth == segments.size()) {
            if (!current->handlers.empty()) {
                result.route = api_route::UNKNOWN;
                return true;
            }
            if (current == &m_root && segments.empty() && !current->handlers.empty()) {
                result.route = api_route::UNKNOWN;
                return true;
            }
            return false;
        }

        const auto& segment = segments[depth];

        auto it = current->children.find(std::string(segment));
        if (it != current->children.end()) {
            if (find_recursive(it->second.get(), segments, depth + 1, result)) {
                return true;
            }
        }

        if (current->param_child) {
            result.params[current->param_child.get()->param_name] = std::string(segment);
            if (find_recursive(current->param_child.get(), segments, depth + 1, result));
                return true;
            result.params.erase(current->param_child->param_name);
        }
        
        if (current->wildcard_child) {
            std::string remaining_path;
            for (size_t i = depth; i < segments.size(); ++i) {
                remaining_path += segments[i];
                if (i < segments.size() - 1) {
                    remaining_path += '/';
                }
            }
            result.params[current->wildcard_child->wildcard_name] = remaining_path;
            result.route = api_route::UNKNOWN;
            return true;
        }
        return false;
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

    [[nodiscard]] match_result find(std::string_view path, http_method method) const {
        match_result result;
        auto segments = split_path(path);
        const node* current = &m_root;

        if (path == "/") {
            auto it = current->handlers.find(method);
            if (it != current->handlers.end()) result.route = it->second;
            return result;
        }

        if (find_recursive(&m_root, segments, 0, result)) {
            const node* final_node = &m_root;
            for (const auto& segment: segments) {
                auto it = final_node->children.find(std::string(segment));
                if (it != final_node->children.end()) final_node = it->second.get();
                else if (final_node->param_child) final_node = final_node->param_child.get();
                else if (final_node->wildcard_child) { 
                    final_node = final_node->wildcard_child.get();
                    break;
                } else {
                    final_node = nullptr;
                    break;
                }
            }

            if (final_node) {
                auto handler_it = final_node->handlers.find(method);
                if (handler_it != final_node->handlers.end()) result.route = handler_it->second;
            }
        }
        return result;
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

} // namespace geecodex::http
#endif // ROUTER_HPP
