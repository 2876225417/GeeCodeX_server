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
import json
import paramiko
import socket
import threading
import time

from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                              QHBoxLayout, QLabel, QLineEdit, QTextEdit, QSpinBox,
                              QPushButton, QFileDialog, QMessageBox, QComboBox,
                              QDateEdit, QFormLayout, QScrollArea, QGroupBox,
                              QCheckBox, QProgressBar, QDialog, QTabWidget,
                              QRadioButton, QButtonGroup, QStatusBar, QToolBar,
                              QMenu)
from PySide6.QtCore import Qt, QDate, Signal, Slot, QThread, QSettings, QTimer
from PySide6.QtGui import QPixmap, QImage, QIcon, QAction

class SFTPManager:
    def __init__(self, host, port, username, password=None, key_file=None):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.key_file = key_file
        self.client = None
        self.sftp = None
        
    def connect(self):
        try:
            self.client = paramiko.SSHClient()
            self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            if self.key_file and os.path.exists(self.key_file):
                key = paramiko.RSAKey.from_private_key_file(self.key_file)
                self.client.connect(self.host, port=self.port, username=self.username, pkey=key, timeout=10)
            else:
                self.client.connect(self.host, port=self.port, username=self.username, password=self.password, timeout=10)
            
            self.sftp = self.client.open_sftp()
            return True
        except Exception as e:
            print(f"SFTP connection error: {e}")
            return False
    
    def disconnect(self):
        if self.sftp:
            self.sftp.close()
        if self.client:
            self.client.close()
        self.sftp = None
        self.client = None
    
    def upload_file(self, local_path, remote_path):
        try:
            if not self.sftp:
                if not self.connect():
                    return False, "Not connected to SFTP server"
            
            # Create remote directory if it doesn't exist
            remote_dir = os.path.dirname(remote_path)
            try:
                self.sftp.stat(remote_dir)
            except FileNotFoundError:
                # Create directory and any parent directories
                current_dir = ""
                for part in remote_dir.split("/"):
                    if not part:
                        continue
                    current_dir += "/" + part
                    try:
                        self.sftp.stat(current_dir)
                    except FileNotFoundError:
                        self.sftp.mkdir(current_dir)
            
            # Upload file
            self.sftp.put(local_path, remote_path)
            return True, "File uploaded successfully"
        except Exception as e:
            return False, f"Error uploading file: {str(e)}"
    
    def test_connection(self):
        try:
            if self.connect():
                # Try to list files in home directory
                self.sftp.listdir()
                self.disconnect()
                return True
            return False
        except Exception as e:
            print(f"SFTP test connection error: {e}")
            return False

class RemoteDatabaseManager:
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
            
    def save_book(self, book_data, remote_pdf_path, remote_cover_path):
        """
        Save book data to remote database with remote file paths
        """
        if not self.connect():
            return False, "Failed to connect to database"
            
        try:
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
                    remote_cover_path if remote_cover_path else None,
                    remote_pdf_path,
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

class ConnectionManager(QThread):
    connection_status = Signal(bool, str, str)  # success, service_name, message
    
    def __init__(self, db_config=None, sftp_config=None):
        super().__init__()
        self.db_config = db_config
        self.sftp_config = sftp_config
        self.stop_flag = False
        
    def run(self):
        while not self.stop_flag:
            # Test database connection
            if self.db_config:
                try:
                    db = RemoteDatabaseManager(
                        self.db_config.get('host', ''),
                        self.db_config.get('port', 5432),
                        self.db_config.get('dbname', ''),
                        self.db_config.get('user', ''),
                        self.db_config.get('password', '')
                    )
                    if db.test_connection():
                        self.connection_status.emit(True, "database", "Connected")
                    else:
                        self.connection_status.emit(False, "database", "Connection failed")
                except Exception as e:
                    self.connection_status.emit(False, "database", f"Error: {str(e)}")
            
            # Test SFTP connection
            if self.sftp_config:
                try:
                    sftp = SFTPManager(
                        self.sftp_config.get('host', ''),
                        self.sftp_config.get('port', 22),
                        self.sftp_config.get('username', ''),
                        self.sftp_config.get('password', ''),
                        self.sftp_config.get('key_file', '')
                    )
                    if sftp.test_connection():
                        self.connection_status.emit(True, "sftp", "Connected")
                    else:
                        self.connection_status.emit(False, "sftp", "Connection failed")
                except Exception as e:
                    self.connection_status.emit(False, "sftp", f"Error: {str(e)}")
            
            # Sleep for 30 seconds before checking again
            for _ in range(30):
                if self.stop_flag:
                    break
                time.sleep(1)
    
    def stop(self):
        self.stop_flag = True

class ServerConfigDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Server Configuration")
        self.setMinimumWidth(500)
        self.settings = QSettings("GeeCodeX", "BookManager")
        
        self.init_ui()
        self.load_settings()
        
    def init_ui(self):
        layout = QVBoxLayout(self)
        
        # Create tabs
        tabs = QTabWidget()
        db_tab = QWidget()
        sftp_tab = QWidget()
        
        tabs.addTab(db_tab, "Database")
        tabs.addTab(sftp_tab, "SFTP")
        
        # Database configuration
        db_layout = QFormLayout(db_tab)
        
        self.db_host = QLineEdit()
        self.db_port = QSpinBox()
        self.db_port.setRange(1, 65535)
        self.db_port.setValue(5432)
        self.db_name = QLineEdit()
        self.db_user = QLineEdit()
        self.db_password = QLineEdit()
        self.db_password.setEchoMode(QLineEdit.Password)
        
        db_layout.addRow("Host:", self.db_host)
        db_layout.addRow("Port:", self.db_port)
        db_layout.addRow("Database Name:", self.db_name)
        db_layout.addRow("Username:", self.db_user)
        db_layout.addRow("Password:", self.db_password)
        
        # SFTP configuration
        sftp_layout = QFormLayout(sftp_tab)
        
        self.sftp_host = QLineEdit()
        self.sftp_port = QSpinBox()
        self.sftp_port.setRange(1, 65535)
        self.sftp_port.setValue(22)
        self.sftp_user = QLineEdit()
        
        # Authentication method
        auth_group = QGroupBox("Authentication Method")
        auth_layout = QVBoxLayout()
        
        self.auth_password = QRadioButton("Password")
        self.auth_key = QRadioButton("SSH Key")
        self.auth_password.setChecked(True)
        
        auth_layout.addWidget(self.auth_password)
        auth_layout.addWidget(self.auth_key)
        auth_group.setLayout(auth_layout)
        
        self.auth_group = QButtonGroup()
        self.auth_group.addButton(self.auth_password, 1)
        self.auth_group.addButton(self.auth_key, 2)
        
        # Password field
        self.sftp_password = QLineEdit()
        self.sftp_password.setEchoMode(QLineEdit.Password)
        
        # Key file field
        key_layout = QHBoxLayout()
        self.sftp_key_file = QLineEdit()
        self.sftp_key_file.setReadOnly(True)
        browse_key = QPushButton("Browse...")
        browse_key.clicked.connect(self.browse_key_file)
        key_layout.addWidget(self.sftp_key_file)
        key_layout.addWidget(browse_key)
        
        # Remote paths
        self.remote_pdf_dir = QLineEdit()
        self.remote_pdf_dir.setPlaceholderText("/path/to/pdfs")
        self.remote_cover_dir = QLineEdit()
        self.remote_cover_dir.setPlaceholderText("/path/to/covers")
        
        sftp_layout.addRow("Host:", self.sftp_host)
        sftp_layout.addRow("Port:", self.sftp_port)
        sftp_layout.addRow("Username:", self.sftp_user)
        sftp_layout.addRow("Authentication:", auth_group)
        sftp_layout.addRow("Password:", self.sftp_password)
        sftp_layout.addRow("SSH Key File:", key_layout)
        sftp_layout.addRow("Remote PDF Directory:", self.remote_pdf_dir)
        sftp_layout.addRow("Remote Cover Directory:", self.remote_cover_dir)
        
        # Connect signals
        self.auth_password.toggled.connect(self.toggle_auth_method)
        
        # Test connection buttons
        test_layout = QHBoxLayout()
        self.test_db_btn = QPushButton("Test Database Connection")
        self.test_sftp_btn = QPushButton("Test SFTP Connection")
        
        self.test_db_btn.clicked.connect(self.test_db_connection)
        self.test_sftp_btn.clicked.connect(self.test_sftp_connection)
        
        test_layout.addWidget(self.test_db_btn)
        test_layout.addWidget(self.test_sftp_btn)
        
        # Dialog buttons
        button_box = QHBoxLayout()
        self.save_btn = QPushButton("Save")
        self.cancel_btn = QPushButton("Cancel")
        
        self.save_btn.clicked.connect(self.accept)
        self.cancel_btn.clicked.connect(self.reject)
        
        button_box.addWidget(self.cancel_btn)
        button_box.addWidget(self.save_btn)
        
        # Add layouts to main layout
        layout.addWidget(tabs)
        layout.addLayout(test_layout)
        layout.addLayout(button_box)
        
    def toggle_auth_method(self, checked):
        self.sftp_password.setEnabled(checked)
        self.sftp_key_file.setEnabled(not checked)
        
    def browse_key_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select SSH Key File", "", "All Files (*)"
        )
        
        if file_path:
            self.sftp_key_file.setText(file_path)
    
    def load_settings(self):
        # Database settings
        self.db_host.setText(self.settings.value("db/host", ""))
        self.db_port.setValue(int(self.settings.value("db/port", 5432)))
        self.db_name.setText(self.settings.value("db/name", ""))
        self.db_user.setText(self.settings.value("db/user", ""))
        self.db_password.setText(self.settings.value("db/password", ""))
        
        # SFTP settings
        self.sftp_host.setText(self.settings.value("sftp/host", ""))
        self.sftp_port.setValue(int(self.settings.value("sftp/port", 22)))
        self.sftp_user.setText(self.settings.value("sftp/user", ""))
        self.sftp_password.setText(self.settings.value("sftp/password", ""))
        self.sftp_key_file.setText(self.settings.value("sftp/key_file", ""))
        
        # Auth method
        use_key = self.settings.value("sftp/use_key", "false") == "true"
        if use_key:
            self.auth_key.setChecked(True)
        else:
            self.auth_password.setChecked(True)
        
        # Remote paths
        self.remote_pdf_dir.setText(self.settings.value("sftp/pdf_dir", "/var/www/geecodex/pdfs"))
        self.remote_cover_dir.setText(self.settings.value("sftp/cover_dir", "/var/www/geecodex/covers"))
        
        # Update UI based on auth method
        self.toggle_auth_method(self.auth_password.isChecked())
    
    def save_settings(self):
        # Database settings
        self.settings.setValue("db/host", self.db_host.text())
        self.settings.setValue("db/port", self.db_port.value())
        self.settings.setValue("db/name", self.db_name.text())
        self.settings.setValue("db/user", self.db_user.text())
        self.settings.setValue("db/password", self.db_password.text())
        
        # SFTP settings
        self.settings.setValue("sftp/host", self.sftp_host.text())
        self.settings.setValue("sftp/port", self.sftp_port.value())
        self.settings.setValue("sftp/user", self.sftp_user.text())
        self.settings.setValue("sftp/password", self.sftp_password.text())
        self.settings.setValue("sftp/key_file", self.sftp_key_file.text())
        self.settings.setValue("sftp/use_key", "true" if self.auth_key.isChecked() else "false")
        
        # Remote paths
        self.settings.setValue("sftp/pdf_dir", self.remote_pdf_dir.text())
        self.settings.setValue("sftp/cover_dir", self.remote_cover_dir.text())
    
    def get_db_config(self):
        return {
            'host': self.db_host.text(),
            'port': self.db_port.value(),
            'dbname': self.db_name.text(),
            'user': self.db_user.text(),
            'password': self.db_password.text()
        }
    
    def get_sftp_config(self):
        return {
            'host': self.sftp_host.text(),
            'port': self.sftp_port.value(),
            'username': self.sftp_user.text(),
            'password': self.sftp_password.text() if self.auth_password.isChecked() else None,
            'key_file': self.sftp_key_file.text() if self.auth_key.isChecked() else None,
            'use_key': self.auth_key.isChecked(),
            'pdf_dir': self.remote_pdf_dir.text(),
            'cover_dir': self.remote_cover_dir.text()
        }
    
    def test_db_connection(self):
        config = self.get_db_config()
        db = RemoteDatabaseManager(
            config['host'], config['port'], config['dbname'],
            config['user'], config['password']
        )
        
        if db.test_connection():
            QMessageBox.information(self, "Database Connection", "Connection successful!")
        else:
            QMessageBox.warning(self, "Database Connection", "Connection failed. Please check your settings.")
    
    def test_sftp_connection(self):
        config = self.get_sftp_config()
        sftp = SFTPManager(
            config['host'], config['port'], config['username'],
            config['password'], config['key_file'] if config['use_key'] else None
        )
        
        if sftp.test_connection():
            QMessageBox.information(self, "SFTP Connection", "Connection successful!")
        else:
            QMessageBox.warning(self, "SFTP Connection", "Connection failed. Please check your settings.")
    
    def accept(self):
        self.save_settings()
        super().accept()

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

class FileUploader(QThread):
    progress_updated = Signal(int, str)  # progress, message
    upload_finished = Signal(bool, str, str, str)  # success, message, remote_pdf_path, remote_cover_path
    
    def __init__(self, sftp_config, pdf_path, cover_path=None):
        super().__init__()
        self.sftp_config = sftp_config
        self.pdf_path = pdf_path
        self.cover_path = cover_path
        
    def run(self):
        try:
            self.progress_updated.emit(10, "Connecting to SFTP server...")
            
            sftp = SFTPManager(
                self.sftp_config['host'],
                self.sftp_config['port'],
                self.sftp_config['username'],
                self.sftp_config['password'],
                self.sftp_config['key_file'] if self.sftp_config['use_key'] else None
            )
            
            if not sftp.connect():
                self.upload_finished.emit(False, "Failed to connect to SFTP server", "", "")
                return
            
            # Generate unique filenames
            unique_id = uuid.uuid4().hex
            pdf_filename = f"{unique_id}.pdf"
            cover_filename = f"{unique_id}.png" if self.cover_path else None
            
            # Get remote paths
            remote_pdf_dir = self.sftp_config.get('pdf_dir', '/var/www/geecodex/pdfs')
            remote_cover_dir = self.sftp_config.get('cover_dir', '/var/www/geecodex/covers')
            
            remote_pdf_path = os.path.join(remote_pdf_dir, pdf_filename).replace('\\', '/')
            remote_cover_path = os.path.join(remote_cover_dir, cover_filename).replace('\\', '/') if cover_filename else None
            
            # Upload PDF file
            self.progress_updated.emit(30, "Uploading PDF file...")
            success, message = sftp.upload_file(self.pdf_path, remote_pdf_path)
            if not success:
                self.upload_finished.emit(False, f"PDF upload failed: {message}", "", "")
                sftp.disconnect()
                return
            
            # Upload cover file if available
            if self.cover_path:
                self.progress_updated.emit(60, "Uploading cover image...")
                success, message = sftp.upload_file(self.cover_path, remote_cover_path)
                if not success:
                    self.upload_finished.emit(False, f"Cover upload failed: {message}", remote_pdf_path, "")
                    sftp.disconnect()
                    return
            
            self.progress_updated.emit(100, "Upload complete")
            sftp.disconnect()
            
            self.upload_finished.emit(True, "Files uploaded successfully", 
                                     remote_pdf_path, remote_cover_path or "")
            
        except Exception as e:
            self.upload_finished.emit(False, f"Upload error: {str(e)}", "", "")

class BookManagerApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("GeeCodeX Book Manager")
        self.setMinimumSize(800, 600)
        
        self.pdf_path = None
        self.cover_path = None
        self.custom_cover = False
        self.db_manager = None
        self.sftp_manager = None
        self.connection_manager = None
        
        self.settings = QSettings("GeeCodeX", "BookManager")
        self.storage_mode = self.settings.value("storage/mode", "local")
        
        self.init_ui()
        self.setup_connections()
        self.load_settings()
        
    def init_ui(self):
        # Main widget and layout
        main_widget = QWidget()
        main_layout = QVBoxLayout(main_widget)
        
        # Create toolbar
        self.create_toolbar()
        
        # Create scroll area for form
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        form_widget = QWidget()
        self.form_layout = QFormLayout(form_widget)
        scroll_area.setWidget(form_widget)
        
        # Storage mode selection
        storage_group = QGroupBox("Storage Mode")
        storage_layout = QHBoxLayout()
        
        self.local_storage = QRadioButton("Local Storage")
        self.cloud_storage = QRadioButton("Cloud Storage")
        
        if self.storage_mode == "local":
            self.local_storage.setChecked(True)
        else:
            self.cloud_storage.setChecked(True)
        
        storage_layout.addWidget(self.local_storage)
        storage_layout.addWidget(self.cloud_storage)
        storage_group.setLayout(storage_layout)
        
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
        self.save_button = QPushButton("Save Book")
        self.save_button.setEnabled(False)
        self.save_button.clicked.connect(self.save_book)
        
        self.clear_button = QPushButton("Clear Form")
        self.clear_button.clicked.connect(self.clear_form)
        
        button_layout.addWidget(self.clear_button)
        button_layout.addWidget(self.save_button)
        
        # Upload progress bar
        self.upload_progress = QProgressBar()
        self.upload_progress.setVisible(False)
        self.upload_status = QLabel("")
        
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
        main_layout.addWidget(storage_group)
        main_layout.addWidget(file_group)
        main_layout.addLayout(form_cover_layout)
        main_layout.addWidget(self.upload_status)
        main_layout.addWidget(self.upload_progress)
        main_layout.addLayout(button_layout)
        
        self.setCentralWidget(main_widget)
        
        # Create status bar
        self.statusBar().showMessage("Ready")
        
        # Add connection status indicators to status bar
        self.db_status = QLabel("DB: Not connected")
        self.sftp_status = QLabel("SFTP: Not connected")
        self.statusBar().addPermanentWidget(self.db_status)
        self.statusBar().addPermanentWidget(self.sftp_status)
        
        # Connect storage mode radio buttons
        self.local_storage.toggled.connect(self.toggle_storage_mode)
        self.cloud_storage.toggled.connect(self.toggle_storage_mode)
        
    def create_toolbar(self):
        toolbar = QToolBar("Main Toolbar")
        self.addToolBar(toolbar)
        
        # Server config action
        server_config_action = QAction("Server Settings", self)
        server_config_action.triggered.connect(self.show_server_config)
        toolbar.addAction(server_config_action)
        
        # Separator
        toolbar.addSeparator()
        
        # Local/Cloud storage actions
        local_action = QAction("Use Local Storage", self)
        local_action.triggered.connect(lambda: self.set_storage_mode("local"))
        
        cloud_action = QAction("Use Cloud Storage", self)
        cloud_action.triggered.connect(lambda: self.set_storage_mode("cloud"))
        
        toolbar.addAction(local_action)
        toolbar.addAction(cloud_action)
        
    def setup_connections(self):
        # Local database connection
        self.db_manager = DatabaseManager(
            host="localhost",
            port=5432,
            dbname="geecodex",
            user="ppqwqqq",
            password="20041025"
        )
        
        # Test local connection
        if self.db_manager.test_connection():
            self.statusBar().showMessage("Local database connected", 3000)
        else:
            QMessageBox.warning(self, "Local Database Connection", 
                               "Could not connect to the local database. Please check your settings.")
    
    def load_settings(self):
        # Load server settings
        db_config = {
            'host': self.settings.value("db/host", ""),
            'port': int(self.settings.value("db/port", 5432)),
            'dbname': self.settings.value("db/name", ""),
            'user': self.settings.value("db/user", ""),
            'password': self.settings.value("db/password", "")
        }
        
        sftp_config = {
            'host': self.settings.value("sftp/host", ""),
            'port': int(self.settings.value("sftp/port", 22)),
            'username': self.settings.value("sftp/user", ""),
            'password': self.settings.value("sftp/password", ""),
            'key_file': self.settings.value("sftp/key_file", ""),
            'use_key': self.settings.value("sftp/use_key", "false") == "true",
            'pdf_dir': self.settings.value("sftp/pdf_dir", "/var/www/geecodex/pdfs"),
            'cover_dir': self.settings.value("sftp/cover_dir", "/var/www/geecodex/covers")
        }
        
        # Start connection manager if cloud storage is selected
        if self.storage_mode == "cloud":
            self.start_connection_manager(db_config, sftp_config)
    
    def start_connection_manager(self, db_config, sftp_config):
        # Stop existing connection manager if running
        if self.connection_manager:
            self.connection_manager.stop()
            self.connection_manager.wait()
        
        # Start new connection manager
        self.connection_manager = ConnectionManager(db_config, sftp_config)
        self.connection_manager.connection_status.connect(self.update_connection_status)
        self.connection_manager.start()
    
    @Slot(bool, str, str)
    def update_connection_status(self, success, service, message):
        if service == "database":
            self.db_status.setText(f"DB: {'Connected' if success else 'Disconnected'}")
            self.db_status.setStyleSheet(f"color: {'green' if success else 'red'}")
        elif service == "sftp":
            self.sftp_status.setText(f"SFTP: {'Connected' if success else 'Disconnected'}")
            self.sftp_status.setStyleSheet(f"color: {'green' if success else 'red'}")
    
    def toggle_storage_mode(self, checked):
        if checked:
            if self.sender() == self.local_storage:
                self.storage_mode = "local"
                self.statusBar().showMessage("Using local storage", 3000)
            else:
                self.storage_mode = "cloud"
                self.statusBar().showMessage("Using cloud storage", 3000)
                
                # Show server config if not configured
                if not self.settings.value("db/host") or not self.settings.value("sftp/host"):
                    self.show_server_config()
                else:
                    # Load server settings
                    db_config = {
                        'host': self.settings.value("db/host", ""),
                        'port': int(self.settings.value("db/port", 5432)),
                        'dbname': self.settings.value("db/name", ""),
                        'user': self.settings.value("db/user", ""),
                        'password': self.settings.value("db/password", "")
                    }
                    
                    sftp_config = {
                        'host': self.settings.value("sftp/host", ""),
                        'port': int(self.settings.value("sftp/port", 22)),
                        'username': self.settings.value("sftp/user", ""),
                        'password': self.settings.value("sftp/password", ""),
                        'key_file': self.settings.value("sftp/key_file", ""),
                        'use_key': self.settings.value("sftp/use_key", "false") == "true",
                        'pdf_dir': self.settings.value("sftp/pdf_dir", "/var/www/geecodex/pdfs"),
                        'cover_dir': self.settings.value("sftp/cover_dir", "/var/www/geecodex/covers")
                    }
                    
                    self.start_connection_manager(db_config, sftp_config)
            
            # Save the setting
            self.settings.setValue("storage/mode", self.storage_mode)
    
    def set_storage_mode(self, mode):
        if mode == "local":
            self.local_storage.setChecked(True)
        else:
            self.cloud_storage.setChecked(True)
    
    def show_server_config(self):
        dialog = ServerConfigDialog(self)
        if dialog.exec():
            # Get new settings
            db_config = dialog.get_db_config()
            sftp_config = dialog.get_sftp_config()
            
            # Start connection manager with new settings
            if self.storage_mode == "cloud":
                self.start_connection_manager(db_config, sftp_config)
    
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
        
        # Save based on storage mode
        if self.storage_mode == "local":
            self.save_local(book_data)
        else:
            self.save_cloud(book_data)
    
    def save_local(self, book_data):
        # Save to local database
        success, message = self.db_manager.save_book(book_data, self.pdf_path, self.cover_path)
        
        if success:
            QMessageBox.information(self, "Success", message)
            self.clear_form()
        else:
            QMessageBox.critical(self, "Error", message)
    
    def save_cloud(self, book_data):
        # Check if server settings are configured
        if not self.settings.value("db/host") or not self.settings.value("sftp/host"):
            QMessageBox.warning(self, "Server Configuration", 
                              "Please configure server settings first.")
            self.show_server_config()
            return
        
        # Get SFTP config
        sftp_config = {
            'host': self.settings.value("sftp/host", ""),
            'port': int(self.settings.value("sftp/port", 22)),
            'username': self.settings.value("sftp/user", ""),
            'password': self.settings.value("sftp/password", ""),
            'key_file': self.settings.value("sftp/key_file", ""),
            'use_key': self.settings.value("sftp/use_key", "false") == "true",
            'pdf_dir': self.settings.value("sftp/pdf_dir", "/var/www/geecodex/pdfs"),
            'cover_dir': self.settings.value("sftp/cover_dir", "/var/www/geecodex/covers")
        }
        
        # Show upload progress
        self.upload_progress.setValue(0)
        self.upload_progress.setVisible(True)
        self.upload_status.setText("Preparing to upload files...")
        self.upload_status.setVisible(True)
        
        # Disable save button during upload
        self.save_button.setEnabled(False)
        
        # Create and start uploader thread
        self.file_uploader = FileUploader(sftp_config, self.pdf_path, self.cover_path)
        self.file_uploader.progress_updated.connect(self.update_upload_progress)
        self.file_uploader.upload_finished.connect(lambda success, message, pdf_path, cover_path: 
                                                 self.files_uploaded(success, message, pdf_path, cover_path, book_data))
        self.file_uploader.start()
    
    @Slot(int, str)
    def update_upload_progress(self, value, message):
        self.upload_progress.setValue(value)
        self.upload_status.setText(message)
    
    @Slot(bool, str, str, str, dict)
    def files_uploaded(self, success, message, remote_pdf_path, remote_cover_path, book_data):
        if not success:
            self.upload_progress.setVisible(False)
            self.upload_status.setVisible(False)
            self.save_button.setEnabled(True)
            QMessageBox.critical(self, "Upload Error", message)
            return
        
        # Files uploaded successfully, now save to remote database
        self.upload_status.setText("Saving to database...")
        
        # Get database config
        db_config = {
            'host': self.settings.value("db/host", ""),
            'port': int(self.settings.value("db/port", 5432)),
            'dbname': self.settings.value("db/name", ""),
            'user': self.settings.value("db/user", ""),
            'password': self.settings.value("db/password", "")
        }
        
        # Connect to remote database
        remote_db = RemoteDatabaseManager(
            db_config['host'], db_config['port'], db_config['dbname'],
            db_config['user'], db_config['password']
        )
        
        # Save book data with remote file paths
        success, db_message = remote_db.save_book(book_data, remote_pdf_path, remote_cover_path)
        
        # Hide progress indicators
        self.upload_progress.setVisible(False)
        self.upload_status.setVisible(False)
        self.save_button.setEnabled(True)
        
        if success:
            QMessageBox.information(self, "Success", 
                                  f"Book uploaded and saved successfully.\n{db_message}")
            self.clear_form()
        else:
            QMessageBox.critical(self, "Database Error", db_message)
    
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
        
        # Hide progress bars
        self.progress_bar.setVisible(False)
        self.upload_progress.setVisible(False)
        self.upload_status.setVisible(False)
    
    def closeEvent(self, event):
        # Stop connection manager when closing
        if self.connection_manager:
            self.connection_manager.stop()
            self.connection_manager.wait()
        event.accept()

# Local database manager (same as original)
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

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = BookManagerApp()
    window.show()
    sys.exit(app.exec())
