# Geecodex_server

# Create New Database

Create the corresponding database in need.

DB: PostgreSQL 

## `codex_books` Table's Info

| Name               | Type                   | Description                                    |
| ----------------   | ---------------------- | ---------------------------------------------- |
| id                 | SERIAL PRIMARY KEY     | Unique Book Identification                     |
| title              | VARCHAR(255) NOT NULL  | Book Title                                     |
| author             | VARCHAR(255)           | Book Author                                    |
| isbn               | VARCHAR(20)            | ISBN Code                                      |
| publisher          | VARCHAR(100)           | Book Publisher                                 |
| publish_date       | DATE                   | Book Pushlished Date                           | 
| language           | VARCHAR(50)            | Language of Book                               |
| page_count         | INTEGER                | Page Count of Book                             |
| description        | TEXT                   | Description of Book                            |
| cover_path         | VARCHAR(500)           | Cover Path of Book (Internal of Server)        |
| pdf_path           | VARCHAR(500)           | PDF File Path of Book (Internal of Server)     |
| file_size_bytes    | BIGINT                 | PDF File Size in Byte                          |
| tags               | TEXT[]                 | Tags of Book                                   |
| category           | VARCHAR(100)           | Category of Book                               |
| access_level       | INTEGER DEFAULT 0      | Access Level of Book                           |
| download_count     | INTEGER DEFAULT 0      | Download Count of Book                         |
| created_at         | TIMESTAMP              | Record Created Date of Book                    |
| updated_at         | TIMESTAMP              | Record Updated Date of Book                    |
| is_active          | BOOLEAN                | Whether book is active                         |

```sql
-- Create Book Table
CREATE TABLE codex_books (
    id SERIAL PRIMARY KEY,                       -- Unique Book Identification
    title VARCHAR(255) NOT NULL,                 -- Book Title
    author VARCHAR(255),                         -- Book Author  
    isbn VARCHAR(20),                            -- ISBN Code    
    publisher VARCHAR(100),                      -- Book Publisher
    publish_date DATE,                           -- Book Pushlished Date
    language VARCHAR(50),                        -- Language of Book    
    page_count INTEGER,                          -- Page Count of Book  
    description TEXT,                            -- Description of Book 
    cover_path VARCHAR(500),                     -- Cover Path of Book (Internal of Server)
    pdf_path VARCHAR(500),                       -- PDF File Path of Book (Internal of Server)
    file_size_bytes BIGINT,                      -- PDF File Size in Byte                     
    tags TEXT[],                                 -- Tags of Book                              
    category VARCHAR(100),                       -- Category of Book                          
    access_level INTEGER DEFAULT 0,              -- Access Level of Book (0=public 1=Registered 2=Premium)
    download_count INTEGER DEFAULT 0,            -- Download Count of Book                    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Record Created Date of Book               
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Record Updated Date of Book               
    is_active BOOLEAN DEFAULT TRUE               -- Whether book is active                    
);

-- Create Index to Optimize Query
CREATE INDEX idx_books_title ON codex_books(title);
CREATE INDEX idx_books_author ON codex_books(author);
CREATE INDEX idx_books_isbn ON codex_books(isbn);
CREATE INDEX idx_books_category ON codex_books(category);
CREATE INDEX idx_books_tags ON codex_books USING GIN(tags);

-- Create Time-updating Trigger
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_codex_books_modtime
BEFORE UPDATE ON codex_books
FOR EACH ROW
EXECUTE FUNCTION update_modified_column();

-- Added comment
COMMENT ON TABLE codex_books IS 'Store metadata and file path of books';
COMMENT ON COLUMN codex_books.id IS 'Unique book identification';
COMMENT ON COLUMN codex_books.title IS 'Title of book';
COMMENT ON COLUMN codex_books.author IS 'Author of book';
COMMENT ON COLUMN codex_books.isbn IS 'ISBN code';
COMMENT ON COLUMN codex_books.publisher IS 'Publisher of book';
COMMENT ON COLUMN codex_books.publish_date IS 'Published date of book';
COMMENT ON COLUMN codex_books.language IS 'Language of book';
COMMENT ON COLUMN codex_books.page_count IS 'Page count of book';
COMMENT ON COLUMN codex_books.description IS 'Description of book';
COMMENT ON COLUMN codex_books.cover_path IS 'Cover file path of book (internal of server), not exposed to user ';
COMMENT ON COLUMN codex_books.pdf_path IS 'PDF file path of book (internal of server), not exposed to user';
COMMENT ON COLUMN codex_books.file_size_bytes IS 'PDF file size (Bytes)';
COMMENT ON COLUMN codex_books.tags IS 'Tags of book';
COMMENT ON COLUMN codex_books.category IS 'Category of book';
COMMENT ON COLUMN codex_books.access_level IS 'Access level of book';
COMMENT ON COLUMN codex_books.download_count IS 'Download count of book';
COMMENT ON COLUMN codex_books.created_at IS 'Record created date';
COMMENT ON COLUMN codex_books.updated_at IS 'Record updated date';
COMMENT ON COLUMN codex_books.is_active IS 'Whether it is accessible';
```

## 

##

##

##


