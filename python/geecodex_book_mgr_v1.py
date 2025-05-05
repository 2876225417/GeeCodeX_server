#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
import tempfile
from pathlib import Path
import fitz  # PyMuPDF
from PIL import Image, ImageQt
import psycopg2
import psycopg2.extras
from datetime import datetime
import shutil
import uuid
import re

from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                              QHBoxLayout, QLabel, QLineEdit, QTextEdit, QSpinBox,
                              QPushButton, QFileDialog, QMessageBox, QComboBox,
                              QDateEdit, QFormLayout, QScrollArea, QGroupBox,
                              QCheckBox, QProgressBar)
from PySide6.QtCore import Qt, QDate, Signal, Slot, QThread
from PySide6.QtGui import QPixmap, QImage, QIcon

class PDFProcessor(QThread):
    progress_updated = Signal(int)
    processing_finished = Signal(dict)
    error_occurred = Signal(str)
    
    def __init__(self, pdf_path):
        super().__init__()
        self.pdf_path = pdf_path
        
    def run(self):
        try:
            self.progress_updated.emit(10)
            # Open PDF file
            doc = fitz.open(self.pdf_path)
            self.progress_updated.emit(30)
            
            # Extract metadata
            metadata = {}
            metadata['title'] = doc.metadata.get('title', '')
            metadata['author'] = doc.metadata.get('author', '')
            metadata['page_count'] = doc.page_count
            metadata['file_size_bytes'] = os.path.getsize(self.pdf_path)
            
            # Get language if available
            metadata['language'] = doc.metadata.get('language', 'en')
            
            # Extract first page as cover
            self.progress_updated.emit(50)
            cover_path = None
            if doc.page_count > 0:
                page = doc.load_page(0)  # First page
                pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
                
                # Save to temporary file
                temp_dir = tempfile.gettempdir()
                cover_path = os.path.join(temp_dir, f"cover_{uuid.uuid4().hex}.png")
                pix.save(cover_path)
                metadata['cover_path'] = cover_path
            
            self.progress_updated.emit(80)
            
            # Try to extract more info if available
            if not metadata['title']:
                # Try to get title from filename
                filename = os.path.basename(self.pdf_path)
                name_without_ext = os.path.splitext(filename)[0]
                metadata['title'] = name_without_ext.replace('_', ' ').replace('-', ' ').title()
            
            # Get publisher if available
            metadata['publisher'] = doc.metadata.get('producer', '')
            
            # Get publication date if available
            pub_date = doc.metadata.get('creationDate', '')
            if pub_date and pub_date.startswith('D:'):
                try:
                    # PDF date format: D:YYYYMMDDHHmmSS
                    year = int(pub_date[2:6])
                    month = int(pub_date[6:8]) if len(pub_date) > 7 else 1
                    day = int(pub_date[8:10]) if len(pub_date) > 9 else 1
                    metadata['publish_date'] = f"{year}-{month:02d}-{day:02d}"
                except (ValueError, IndexError):
                    metadata['publish_date'] = None
            else:
                metadata['publish_date'] = None
            
            # Close the document
            doc.close()
            
            self.progress_updated.emit(100)
            self.processing_finished.emit(metadata)
            
        except Exception as e:
            self.error_occurred.emit(f"Error processing PDF: {str(e)}")

class DatabaseManager:
    def __init__(self, host, port, dbname, user, password):
        self.connection_params = {
            'host': host,
            'port': port,
            'dbname': dbname,
            'user': user,
            'password': password
        }
        self.conn = None
        
    def connect(self):
        try:
            self.conn = psycopg2.connect(**self.connection_params)
            return True
        except Exception as e:
            print(f"Database connection error: {e}")
            return False
            
    def disconnect(self):
        if self.conn:
            self.conn.close()
            
    def test_connection(self):
        try:
            self.connect()
            with self.conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                result = cursor.fetchone()
                return result is not None
        except Exception as e:
            print(f"Connection test failed: {e}")
            return False
        finally:
            self.disconnect()
            
    def save_book(self, book_data, pdf_path, cover_path):
        """
        Save book data to database and copy files to storage
        """
        if not self.connect():
            return False, "Failed to connect to database"
            
        try:
            # Create storage directories if they don't exist
            storage_base = os.path.expanduser("~/geecodex_storage")
            pdf_storage = os.path.join(storage_base, "pdfs")
            cover_storage = os.path.join(storage_base, "covers")
            
            for directory in [pdf_storage, cover_storage]:
                os.makedirs(directory, exist_ok=True)
                
            # Generate unique filenames
            unique_id = uuid.uuid4().hex
            pdf_filename = f"{unique_id}.pdf"
            cover_filename = f"{unique_id}.png"
            
            # Copy files to storage
            pdf_dest_path = os.path.join(pdf_storage, pdf_filename)
            cover_dest_path = os.path.join(cover_storage, cover_filename)
            
            shutil.copy2(pdf_path, pdf_dest_path)
            if cover_path:
                shutil.copy2(cover_path, cover_dest_path)
                
            # Prepare data for insertion
            with self.conn.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO codex_books (
                        title, author, isbn, publisher, publish_date,
                        language, page_count, description, cover_path,
                        pdf_path, file_size_bytes, tags, category,
                        access_level, created_at, updated_at, is_active
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 
                        NOW(), NOW(), %s
                    ) RETURNING id
                """, (
                    book_data.get('title', ''),
                    book_data.get('author', ''),
                    book_data.get('isbn', ''),
                    book_data.get('publisher', ''),
                    book_data.get('publish_date'),
                    book_data.get('language', 'en'),
                    book_data.get('page_count', 0),
                    book_data.get('description', ''),
                    cover_dest_path if cover_path else None,
                    pdf_dest_path,
                    book_data.get('file_size_bytes', 0),
                    book_data.get('tags', []),
                    book_data.get('category', ''),
                    book_data.get('access_level', 0),
                    book_data.get('is_active', True)
                ))
                
                book_id = cursor.fetchone()[0]
                self.conn.commit()
                
            return True, f"Book saved successfully with ID: {book_id}"
            
        except Exception as e:
            self.conn.rollback()
            return False, f"Error saving book: {str(e)}"
        finally:
            self.disconnect()

class BookManagerApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("GeeCodeX Book Manager")
        self.setMinimumSize(800, 600)
        
        self.pdf_path = None
        self.cover_path = None
        self.custom_cover = False
        self.db_manager = None
        
        self.init_ui()
        self.setup_db_connection()
        
    def init_ui(self):
        # Main widget and layout
        main_widget = QWidget()
        main_layout = QVBoxLayout(main_widget)
        
        # Create scroll area for form
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        form_widget = QWidget()
        self.form_layout = QFormLayout(form_widget)
        scroll_area.setWidget(form_widget)
        
        # File selection area
        file_group = QGroupBox("PDF File")
        file_layout = QVBoxLayout()
        
        file_select_layout = QHBoxLayout()
        self.file_path_label = QLineEdit()
        self.file_path_label.setReadOnly(True)
        self.file_path_label.setPlaceholderText("Select a PDF file...")
        browse_button = QPushButton("Browse...")
        browse_button.clicked.connect(self.browse_pdf)
        
        file_select_layout.addWidget(self.file_path_label)
        file_select_layout.addWidget(browse_button)
        
        # Progress bar for PDF processing
        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        
        file_layout.addLayout(file_select_layout)
        file_layout.addWidget(self.progress_bar)
        file_group.setLayout(file_layout)
        
        # Book metadata form
        metadata_group = QGroupBox("Book Metadata")
        metadata_layout = QFormLayout()
        
        # Basic info
        self.title_input = QLineEdit()
        self.author_input = QLineEdit()
        self.isbn_input = QLineEdit()
        self.publisher_input = QLineEdit()
        
        # Publication date
        self.publish_date_input = QDateEdit()
        self.publish_date_input.setCalendarPopup(True)
        self.publish_date_input.setDate(QDate.currentDate())
        
        # Language
        self.language_input = QComboBox()
        for lang in ["English", "Spanish", "French", "German", "Chinese", "Japanese", "Other"]:
            self.language_input.addItem(lang)
            
        # Page count
        self.page_count_input = QSpinBox()
        self.page_count_input.setRange(1, 10000)
        
        # Category
        self.category_input = QComboBox()
        for category in ["Programming", "Science", "Mathematics", "Fiction", "Non-Fiction", 
                         "History", "Technology", "Art", "Philosophy", "Other"]:
            self.category_input.addItem(category)
            
        # Access level
        self.access_level_input = QComboBox()
        self.access_level_input.addItem("Public (0)", 0)
        self.access_level_input.addItem("Registered Users (1)", 1)
        self.access_level_input.addItem("Premium Users (2)", 2)
        
        # Description
        self.description_input = QTextEdit()
        self.description_input.setPlaceholderText("Enter book description...")
        
        # Tags
        self.tags_input = QLineEdit()
        self.tags_input.setPlaceholderText("Enter tags separated by commas...")
        
        # Is active
        self.is_active_input = QCheckBox("Book is available for download")
        self.is_active_input.setChecked(True)
        
        # Add fields to form
        metadata_layout.addRow("Title:", self.title_input)
        metadata_layout.addRow("Author:", self.author_input)
        metadata_layout.addRow("ISBN:", self.isbn_input)
        metadata_layout.addRow("Publisher:", self.publisher_input)
        metadata_layout.addRow("Publication Date:", self.publish_date_input)
        metadata_layout.addRow("Language:", self.language_input)
        metadata_layout.addRow("Page Count:", self.page_count_input)
        metadata_layout.addRow("Category:", self.category_input)
        metadata_layout.addRow("Access Level:", self.access_level_input)
        metadata_layout.addRow("Tags:", self.tags_input)
        metadata_layout.addRow("Description:", self.description_input)
        metadata_layout.addRow("", self.is_active_input)
        
        metadata_group.setLayout(metadata_layout)
        
        # Cover image area
        cover_group = QGroupBox("Book Cover")
        cover_layout = QVBoxLayout()
        
        self.cover_preview = QLabel("No cover image")
        self.cover_preview.setAlignment(Qt.AlignCenter)
        self.cover_preview.setMinimumSize(200, 280)
        self.cover_preview.setStyleSheet("background-color: #f0f0f0; border: 1px solid #ddd;")
        
        cover_buttons_layout = QHBoxLayout()
        self.auto_cover_btn = QPushButton("Extract from PDF")
        self.auto_cover_btn.setEnabled(False)
        self.auto_cover_btn.clicked.connect(self.extract_cover)
        
        self.custom_cover_btn = QPushButton("Custom Cover...")
        self.custom_cover_btn.clicked.connect(self.browse_cover)
        
        cover_buttons_layout.addWidget(self.auto_cover_btn)
        cover_buttons_layout.addWidget(self.custom_cover_btn)
        
        cover_layout.addWidget(self.cover_preview)
        cover_layout.addLayout(cover_buttons_layout)
        cover_group.setLayout(cover_layout)
        
        # Action buttons
        button_layout = QHBoxLayout()
        self.save_button = QPushButton("Save to Database")
        self.save_button.setEnabled(False)
        self.save_button.clicked.connect(self.save_book)
        
        self.clear_button = QPushButton("Clear Form")
        self.clear_button.clicked.connect(self.clear_form)
        
        button_layout.addWidget(self.clear_button)
        button_layout.addWidget(self.save_button)
        
        # Layout the form and cover side by side
        form_cover_layout = QHBoxLayout()
        
        left_layout = QVBoxLayout()
        left_layout.addWidget(metadata_group)
        
        right_layout = QVBoxLayout()
        right_layout.addWidget(cover_group)
        right_layout.addStretch()
        
        form_cover_layout.addLayout(left_layout, 3)
        form_cover_layout.addLayout(right_layout, 1)
        
        # Add all components to main layout
        main_layout.addWidget(file_group)
        main_layout.addLayout(form_cover_layout)
        main_layout.addLayout(button_layout)
        
        self.setCentralWidget(main_widget)
        
    def setup_db_connection(self):
        # You can hard-code these for development or use a settings dialog
        self.db_manager = DatabaseManager(
            host="localhost",
            port=5432,
            dbname="geecodex",
            user="ppqwqqq",
            password="20041025"
        )
        
        # Test connection
        if self.db_manager.test_connection():
            self.statusBar().showMessage("Database connected", 3000)
        else:
            QMessageBox.warning(self, "Database Connection", 
                               "Could not connect to the database. Please check your settings.")
    
    def browse_pdf(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select PDF File", "", "PDF Files (*.pdf)"
        )
        
        if file_path:
            self.pdf_path = file_path
            self.file_path_label.setText(file_path)
            self.auto_cover_btn.setEnabled(True)
            self.save_button.setEnabled(True)
            
            # Process the PDF
            self.process_pdf(file_path)
    
    def process_pdf(self, pdf_path):
        # Show progress bar
        self.progress_bar.setValue(0)
        self.progress_bar.setVisible(True)
        
        # Create and start worker thread
        self.pdf_processor = PDFProcessor(pdf_path)
        self.pdf_processor.progress_updated.connect(self.update_progress)
        self.pdf_processor.processing_finished.connect(self.pdf_processed)
        self.pdf_processor.error_occurred.connect(self.pdf_processing_error)
        self.pdf_processor.start()
    
    @Slot(int)
    def update_progress(self, value):
        self.progress_bar.setValue(value)
    
    @Slot(dict)
    def pdf_processed(self, metadata):
        # Hide progress bar
        self.progress_bar.setVisible(False)
        
        # Update form with extracted metadata
        self.title_input.setText(metadata.get('title', ''))
        self.author_input.setText(metadata.get('author', ''))
        self.page_count_input.setValue(metadata.get('page_count', 1))
        
        # Set language
        language = metadata.get('language', 'en')
        language_map = {
            'en': 'English',
            'es': 'Spanish',
            'fr': 'French',
            'de': 'German',
            'zh': 'Chinese',
            'ja': 'Japanese'
        }
        lang_index = self.language_input.findText(language_map.get(language, 'English'))
        if lang_index >= 0:
            self.language_input.setCurrentIndex(lang_index)
        
        # Set publication date if available
        if metadata.get('publish_date'):
            try:
                date = QDate.fromString(metadata['publish_date'], "yyyy-MM-dd")
                self.publish_date_input.setDate(date)
            except:
                pass
                
        # Set publisher
        self.publisher_input.setText(metadata.get('publisher', ''))
        
        # Set cover image if available
        if 'cover_path' in metadata and metadata['cover_path']:
            self.cover_path = metadata['cover_path']
            self.update_cover_preview(self.cover_path)
            self.custom_cover = False
    
    @Slot(str)
    def pdf_processing_error(self, error_message):
        self.progress_bar.setVisible(False)
        QMessageBox.warning(self, "PDF Processing Error", error_message)
    
    def browse_cover(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select Cover Image", "", "Image Files (*.png *.jpg *.jpeg)"
        )
        
        if file_path:
            self.cover_path = file_path
            self.update_cover_preview(file_path)
            self.custom_cover = True
    
    def extract_cover(self):
        if self.pdf_path:
            self.process_pdf(self.pdf_path)
    
    def update_cover_preview(self, image_path):
        if not image_path or not os.path.exists(image_path):
            return
            
        pixmap = QPixmap(image_path)
        if not pixmap.isNull():
            pixmap = pixmap.scaled(200, 280, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            self.cover_preview.setPixmap(pixmap)
    
    def save_book(self):
        if not self.pdf_path:
            QMessageBox.warning(self, "Missing File", "Please select a PDF file first.")
            return
            
        # Validate form
        title = self.title_input.text().strip()
        if not title:
            QMessageBox.warning(self, "Validation Error", "Title is required.")
            return
        
        # Collect form data
        book_data = {
            'title': title,
            'author': self.author_input.text().strip(),
            'isbn': self.isbn_input.text().strip(),
            'publisher': self.publisher_input.text().strip(),
            'publish_date': self.publish_date_input.date().toString("yyyy-MM-dd"),
            'language': self.language_input.currentText(),
            'page_count': self.page_count_input.value(),
            'description': self.description_input.toPlainText().strip(),
            'category': self.category_input.currentText(),
            'access_level': self.access_level_input.currentData(),
            'is_active': self.is_active_input.isChecked(),
            'file_size_bytes': os.path.getsize(self.pdf_path) if self.pdf_path else 0
        }
        
        # Process tags
        tags_text = self.tags_input.text().strip()
        if tags_text:
            # Split by comma and remove whitespace
            tags = [tag.strip() for tag in tags_text.split(',') if tag.strip()]
            book_data['tags'] = tags
        else:
            book_data['tags'] = []
        
        # Save to database
        success, message = self.db_manager.save_book(book_data, self.pdf_path, self.cover_path)
        
        if success:
            QMessageBox.information(self, "Success", message)
            self.clear_form()
        else:
            QMessageBox.critical(self, "Error", message)
    
    def clear_form(self):
        # Clear all form fields
        self.pdf_path = None
        self.cover_path = None
        self.custom_cover = False
        
        self.file_path_label.clear()
        self.title_input.clear()
        self.author_input.clear()
        self.isbn_input.clear()
        self.publisher_input.clear()
        self.publish_date_input.setDate(QDate.currentDate())
        self.language_input.setCurrentIndex(0)
        self.page_count_input.setValue(1)
        self.category_input.setCurrentIndex(0)
        self.access_level_input.setCurrentIndex(0)
        self.tags_input.clear()
        self.description_input.clear()
        self.is_active_input.setChecked(True)
        
        # Reset cover preview
        self.cover_preview.setText("No cover image")
        self.cover_preview.setPixmap(QPixmap())
        
        # Disable buttons
        self.auto_cover_btn.setEnabled(False)
        self.save_button.setEnabled(False)
        
        # Hide progress bar
        self.progress_bar.setVisible(False)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = BookManagerApp()
    window.show()
    sys.exit(app.exec())
