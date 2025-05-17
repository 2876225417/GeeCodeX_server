#ifndef ROUTES_BOOKS_HPP
#define ROUTES_BOOKS_HPP

#include "http/router.hpp"
#include <http/router_defs.hpp>
#include <span>
#include <array>
#include <vector>
#include <unordered_map>

namespace geecodex::http {

void handle_download_pdf(http_connection &conn);
void handle_fetch_pdf_cover(http_connection &conn);
void handle_fetch_latest_books(http_connection &conn);
void handle_comment_book(http_connection &conn);
void handle_score_book(http_connection &conn);

static constexpr route_info book_route_definitions_array[] = {
    {"/geecodex/books/latest",          http_method::GET,   api_route::FETCH_LATEST_BOOKS},
    {"/geecodex/books/cover/",          http_method::GET,   api_route::FETCH_PDF_COVER,     route_match_type::PREFIX},
    {"/geecodex/books/",                http_method::GET,   api_route::DOWNLOAD_PDF,        route_match_type::PREFIX},
    {"/geecodex/books/comment/",        http_method::POST,  api_route::COMMENT_BOOK,        route_match_type::PREFIX},     
    {"/geecodex/books/score/",          http_method::POST,  api_route::SCORE_BOOK,          route_match_type::PREFIX},
};

inline std::span<const route_info> get_book_route_definitions() {
    return {book_route_definitions_array, std::size(book_route_definitions_array)};
}

inline void register_book_handlers(std::unordered_map<api_route, route_handler_func>& handlers) {
    handlers[api_route::DOWNLOAD_PDF] = handle_download_pdf;
    handlers[api_route::FETCH_PDF_COVER] = handle_fetch_pdf_cover;
    handlers[api_route::FETCH_LATEST_BOOKS] = handle_fetch_latest_books;
    handlers[api_route::COMMENT_BOOK] = handle_comment_book;
    handlers[api_route::SCORE_BOOK] = handle_score_book;
}

}   // NAMESPACE GEECODEX::HTTP

#endif  // ROUTES_BOOKS_HPP