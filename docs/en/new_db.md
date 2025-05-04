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

## 'app_updates' Table's Info
```sql
CREATE TABLE app_updates (
    id SERIAL PRIMARY KEY,                      -- Unique ID for the update record
    platform VARCHAR(50) NOT NULL DEFAULT 'android', -- Platform (e.g., 'android', 'ios') - Index recommended
    package_name VARCHAR(255) NOT NULL,             -- Android application ID (e.g., 'com.yourcompany.geecodexapp') - Index recommended
    version_code INTEGER NOT NULL,                  -- Integer version code (must increment for each release) - Index recommended
    version_name VARCHAR(100) NOT NULL,             -- User-visible version name (e.g., '1.0.2', '2.0-beta')
    channel VARCHAR(50) NOT NULL DEFAULT 'stable',  -- Release channel (e.g., 'stable', 'beta', 'alpha') - Index recommended
    architecture VARCHAR(50) DEFAULT 'universal',    -- CPU architecture (e.g., 'universal', 'arm64-v8a', 'armeabi-v7a', 'x86_64') - Index recommended
    release_notes TEXT,                             -- Description of changes in this version (changelog)
    download_url VARCHAR(500) NOT NULL,             -- URL to download the APK file
    file_size_bytes BIGINT,                         -- Size of the APK file in bytes (optional but helpful)
    file_hash VARCHAR(128),                         -- SHA-256 hash of the APK file for integrity check (hex string, optional but highly recommended)
    hash_algorithm VARCHAR(20) DEFAULT 'SHA-256',  -- Algorithm used for the hash (e.g., 'SHA-256', 'SHA-512')
    min_os_version VARCHAR(50),                     -- Minimum required OS version (e.g., 'API 21', 'Android 5.0') (optional)
    is_forced BOOLEAN DEFAULT FALSE,                -- Whether this update is mandatory
    released_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- When this version was published - Index recommended
    is_active BOOLEAN DEFAULT TRUE,                 -- Allows deactivating an update record without deleting
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Record creation time
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP  -- Record update time
);

-- Indexes for common query patterns
CREATE INDEX idx_app_updates_lookup ON app_updates(platform, package_name, channel, architecture, is_active, version_code);
CREATE INDEX idx_app_updates_released_at ON app_updates(released_at);

-- Trigger for updated_at (reuse or create similar to codex_books)
CREATE TRIGGER update_app_updates_modtime
BEFORE UPDATE ON app_updates
FOR EACH ROW
EXECUTE FUNCTION update_modified_column(); -- Assuming update_modified_column function already exists

-- Comments
COMMENT ON TABLE app_updates IS 'Stores metadata for application updates';
COMMENT ON COLUMN app_updates.platform IS 'Target platform (e.g., android, ios)';
COMMENT ON COLUMN app_updates.package_name IS 'Unique identifier for the application (e.g., Android package name)';
COMMENT ON COLUMN app_updates.version_code IS 'Integer version code, used for comparison (must increment)';
COMMENT ON COLUMN app_updates.version_name IS 'User-friendly version string';
COMMENT ON COLUMN app_updates.channel IS 'Release channel (stable, beta, etc.)';
COMMENT ON COLUMN app_updates.architecture IS 'Target CPU architecture (universal, arm64-v8a, etc.)';
COMMENT ON COLUMN app_updates.release_notes IS 'Changelog or description of changes';
COMMENT ON COLUMN app_updates.download_url IS 'Direct URL to download the update package (e.g., APK)';
COMMENT ON COLUMN app_updates.file_size_bytes IS 'Size of the update package in bytes';
COMMENT ON COLUMN app_updates.file_hash IS 'Cryptographic hash (e.g., SHA-256 hex) of the package for integrity verification';
COMMENT ON COLUMN app_updates.hash_algorithm IS 'Algorithm used for file_hash';
COMMENT ON COLUMN app_updates.min_os_version IS 'Minimum OS version required for this update';
COMMENT ON COLUMN app_updates.is_forced IS 'Flag indicating if the update is mandatory for the user';
COMMENT ON COLUMN app_updates.released_at IS 'Timestamp when this version was made available';
COMMENT ON COLUMN app_updates.is_active IS 'Flag to enable/disable this update record';
```
##

##

##


