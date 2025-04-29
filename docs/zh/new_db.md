# Geecodex_server

## 创建数据库
创建如下数据库:

数据库: PostgreSQL 

## `codex_books` 表信息

| 字段                | 类型                   | 描述             |
| ----------------   | ---------------------- | --------------- |
| id                 | SERIAL PRIMARY KEY     | 书籍唯标识        |
| title              | VARCHAR(255) NOT NULL  | 书籍标题          |
| author             | VARCHAR(255)           | 作者             |
| isbn               | VARCHAR(20)            | ISBN号          |
| publisher          | VARCHAR(100)           | 出版商           |
| publish_date       | DATE                   | 出版日期         |    
| language           | VARCHAR(50)            | 书籍语言         |
| page_count         | INTEGER                | 页数            |
| description        | TEXT                   | 书籍简介        |
| cover_path         | VARCHAR(500)           | 封面图片存储路径  |
| pdf_path           | VARCHAR(500)           | PDF文件存储路径  |
| file_size_bytes    | BIGINT                 | 文件大小（字节）  |
| tags               | TEXT[]                 | 书籍标签        |
| category           | VARCHAR(100)           | 分类            |
| access_level       | INTEGER DEFAULT 0      | 访问级别        |
| download_count     | INTEGER DEFAULT 0      | 下载次数        |
| created_at         | TIMESTAMP              | 创建时间        |
| updated_at         | TIMESTAMP              | 更新时间        |
| is_active          | BOOLEAN                | 是否可用        |

```sql
-- 创建书籍表
CREATE TABLE codex_books (
    id SERIAL PRIMARY KEY,                       -- 书籍唯一标识符
    title VARCHAR(255) NOT NULL,                 -- 书籍标题
    author VARCHAR(255),                         -- 作者
    isbn VARCHAR(20),                            -- ISBN号
    publisher VARCHAR(100),                      -- 出版商
    publish_date DATE,                           -- 出版日期
    language VARCHAR(50),                        -- 书籍语言
    page_count INTEGER,                          -- 页数
    description TEXT,                            -- 书籍简介
    cover_path VARCHAR(500),                     -- 封面图片存储路径（服务器内部路径）
    pdf_path VARCHAR(500),                       -- PDF文件存储路径（服务器内部路径）
    file_size_bytes BIGINT,                      -- 文件大小（字节）
    tags TEXT[],                                 -- 标签数组
    category VARCHAR(100),                       -- 分类
    access_level INTEGER DEFAULT 0,              -- 访问级别（0=公开，1=注册用户，2=付费用户等）
    download_count INTEGER DEFAULT 0,            -- 下载次数
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 创建时间
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 更新时间
    is_active BOOLEAN DEFAULT TRUE               -- 是否可用
);

-- 创建索引以提高查询性能
CREATE INDEX idx_books_title ON codex_books(title);
CREATE INDEX idx_books_author ON codex_books(author);
CREATE INDEX idx_books_isbn ON codex_books(isbn);
CREATE INDEX idx_books_category ON codex_books(category);
CREATE INDEX idx_books_tags ON codex_books USING GIN(tags);

-- 创建更新时间触发器
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

-- 添加注释
COMMENT ON TABLE codex_books IS '存储书籍元数据和文件路径信息';
COMMENT ON COLUMN codex_books.id IS '书籍唯一标识符';
COMMENT ON COLUMN codex_books.title IS '书籍标题';
COMMENT ON COLUMN codex_books.author IS '作者名称';
COMMENT ON COLUMN codex_books.isbn IS '国际标准书号';
COMMENT ON COLUMN codex_books.publisher IS '出版社名称';
COMMENT ON COLUMN codex_books.publish_date IS '出版日期';
COMMENT ON COLUMN codex_books.language IS '书籍语言';
COMMENT ON COLUMN codex_books.page_count IS '书籍页数';
COMMENT ON COLUMN codex_books.description IS '书籍简介或摘要';
COMMENT ON COLUMN codex_books.cover_path IS '封面图片在服务器上的存储路径，不直接暴露给用户';
COMMENT ON COLUMN codex_books.pdf_path IS 'PDF文件在服务器上的存储路径，不直接暴露给用户';
COMMENT ON COLUMN codex_books.file_size_bytes IS 'PDF文件大小，以字节为单位';
COMMENT ON COLUMN codex_books.tags IS '相关标签数组';
COMMENT ON COLUMN codex_books.category IS '书籍分类';
COMMENT ON COLUMN codex_books.access_level IS '访问权限级别';
COMMENT ON COLUMN codex_books.download_count IS '下载次数统计';
COMMENT ON COLUMN codex_books.created_at IS '记录创建时间';
COMMENT ON COLUMN codex_books.updated_at IS '记录最后更新时间';
COMMENT ON COLUMN codex_books.is_active IS '标记记录是否可用';
```


## 


##

##

##

