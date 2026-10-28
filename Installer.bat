@echo off
:: ==============================================================================
:: SKRIP OTOMASI SETUP SISTEM PRESENSI WAJAH REAL-TIME
:: Arsitektur: Laravel 13 (Web) + FastAPI (AI/Computer Vision) + MySQL + Redis + Elasticsearch
:: ==============================================================================

:: Memastikan direktori kerja aktif selalu merujuk ke lokasi file installer.bat ini disimpan
cd /d "%~dp0"

echo [1/6] Memeriksa & Membuat Struktur Folder Service FastAPI...
:: Membuat hirarki folder tempat penyimpanan source code Python dan dataset wajah
if not exist "fastapi-service" mkdir fastapi-service
if not exist "fastapi-service\app" mkdir fastapi-service\app
if not exist "fastapi-service\app\models" mkdir fastapi-service\app\models
if not exist "fastapi-service\app\services" mkdir fastapi-service\app\services
if not exist "fastapi-service\dataset" mkdir fastapi-service\dataset
if not exist "fastapi-service\trainer" mkdir fastapi-service\trainer

:: Penjelasan ke Mahasiswa:
:: Dockerfile digunakan untuk mendefinisikan environment runtime Python 3.11, 
:: menginstal dependency sistem yang dibutuhkan OpenCV (tanpa GUI), dan menyiapkan uvicorn server.
if not exist "fastapi-service\Dockerfile" (
    (
    echo FROM python:3.11-slim
    echo WORKDIR /app
    echo RUN apt-get update ^&^& apt-get install -y --no-install-recommends build-essential ^&^& rm -rf /var/lib/apt/lists/*
    echo COPY requirements.txt .
    echo RUN pip install --no-cache-dir -r requirements.txt
    echo COPY . .
    echo EXPOSE 8000
    echo CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
    ) > fastapi-service\Dockerfile
)

:: Penjelasan ke Mahasiswa:
:: requirements.txt mendaftar seluruh library Python yang digunakan:
:: - FastAPI & Uvicorn: Web framework & Server ASGI async
:: - OpenCV Headless: Pengolahan citra & algoritma Haar Cascade / LBPH
:: - SQLAlchemy & PyMySQL: ORM dan driver database MySQL
:: - Redis & Elasticsearch: Caching layer dan search engine analitik
if not exist "fastapi-service\requirements.txt" (
    (
    echo fastapi==0.115.0
    echo uvicorn[standard]==0.31.0
    echo opencv-contrib-python-headless==4.10.0.84
    echo numpy==2.1.1
    echo python-multipart==0.0.12
    echo sqlalchemy==2.0.35
    echo pymysql==1.1.1
    echo cryptography==43.0.1
    echo redis==5.0.8
    echo elasticsearch==8.15.0
    ) > fastapi-service\requirements.txt
)

:: Membuat placeholder file skrip Python agar arsitektur OOP siap diisi oleh modul layanan
if not exist "fastapi-service\main.py" type nul > fastapi-service\main.py
if not exist "fastapi-service\app\__init__.py" type nul > fastapi-service\app\__init__.py
if not exist "fastapi-service\app\database.py" type nul > fastapi-service\app\database.py
if not exist "fastapi-service\app\redis_client.py" type nul > fastapi-service\app\redis_client.py
if not exist "fastapi-service\app\es_client.py" type nul > fastapi-service\app\es_client.py
if not exist "fastapi-service\app\models\__init__.py" type nul > fastapi-service\app\models\__init__.py
if not exist "fastapi-service\app\models\orm.py" type nul > fastapi-service\app\models\orm.py
if not exist "fastapi-service\app\models\student.py" type nul > fastapi-service\app\models\student.py
if not exist "fastapi-service\app\services\__init__.py" type nul > fastapi-service\app\services\__init__.py
if not exist "fastapi-service\app\services\face_detector.py" type nul > fastapi-service\app\services\face_detector.py
if not exist "fastapi-service\app\services\face_recognizer.py" type nul > fastapi-service\app\services\face_recognizer.py

echo [2/6] Memeriksa & Mengunduh Project Laravel 13...
:: Flag --no-scripts digunakan agar composer tidak memicu prompt interaktif pihak ketiga (seperti installer NVM)
if not exist "laravel-app\artisan" (
    echo Mengunduh Framework Laravel...
    call composer create-project laravel/laravel laravel-app --no-scripts
)

:: Penjelasan ke Mahasiswa:
:: Dockerfile Laravel menggunakan image PHP 8.4-FPM untuk menyesuaikan requirement Laravel 13 terbaru,
:: serta menginstal ekstensi PDO MySQL untuk DB connection dan GD Library untuk pengolahan gambar pendukung.
if not exist "laravel-app\Dockerfile" (
    (
    echo FROM php:8.4-fpm
    echo WORKDIR /var/www
    echo RUN apt-get update ^&^& apt-get install -y build-essential libpng-dev libjpeg62-turbo-dev libfreetype6-dev zip unzip git curl libonig-dev libzip-dev
    echo RUN docker-php-ext-install pdo_mysql mbstring zip exif pcntl
    echo RUN docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/
    echo RUN docker-php-ext-install gd
    echo COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
    echo COPY . /var/www
    echo EXPOSE 9000
    echo CMD ["php-fpm"]
    ) > laravel-app\Dockerfile
)

echo [3/6] Konfigurasi Environment Variable (.env)...
:: File .env utama di tingkat root digunakan oleh Docker Compose untuk memetakan port dan kredensial database
if not exist ".env" (
    echo Membuat konfigurasi .env root...
    (
    echo APP_NAME=FaceRecognitionApp
    echo ENV=development
    echo.
    echo MYSQL_HOST=mysql_db
    echo MYSQL_PORT=3306
    echo MYSQL_DATABASE=db_face_recognition
    echo MYSQL_USER=user_face
    echo MYSQL_PASSWORD=user_password_123
    echo MYSQL_ROOT_PASSWORD=root_password_123
    echo.
    echo REDIS_HOST=redis_service
    echo REDIS_PORT=6379
    echo.
    echo ELASTICSEARCH_HOST=http://elasticsearch_service:9200
    echo FASTAPI_PORT=8000
    echo LARAVEL_PORT=8080
    ) > .env
)

:: 2. Membaca isi file .env root dan memasukkannya ke variable environment batch
echo Membaca konfigurasi dari file .env root...
for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    :: Abaikan baris kosong atau baris komentar (yang diawali tanda #)
    echo %%A | findstr /r "^#" >nul
    if errorlevel 1 (
        if not "%%A"=="" set "%%A=%%B"
    )
)

:: Menyelaraskan file .env Laravel agar service container dapat saling berkomunikasi via DNS Docker Network
if not exist "laravel-app\.env" (
    echo Menyinkronkan .env ke aplikasi Laravel...
    (
    echo APP_NAME=%APP_NAME%
    echo APP_ENV=local
    echo APP_KEY=
    echo APP_DEBUG=true
    echo APP_URL=http://localhost:%LARAVEL_PORT%
    echo.
    echo DB_CONNECTION=mysql
    echo DB_HOST=%MYSQL_HOST%
    echo DB_PORT=%MYSQL_PORT%
    echo DB_DATABASE=%MYSQL_DATABASE%
    echo DB_USERNAME=%MYSQL_USER%
    echo DB_PASSWORD=%MYSQL_PASSWORD%
    echo.
    echo REDIS_HOST=%REDIS_HOST%
    echo REDIS_PORT=%REDIS_PORT%
    echo.
    echo ELASTICSEARCH_HOST=%ELASTICSEARCH_HOST%
    echo FASTAPI_SERVICE_URL=http://fastapi-service:%FASTAPI_PORT%
    ) > laravel-app\.env
)

echo [4/6] Build dan Orkestrasi Docker Containers...
:: Membangun seluruh image (FastAPI, Laravel, Nginx) dan mengaktifkan service (MySQL, Redis, ES)
call docker-compose up -d --build

echo [5/6] Menunggu Inisialisasi Service Database dan Search Engine...
:: Mengalokasikan jeda waktu 10 detik untuk memastikan daemon MySQL dan Elasticsearch siap menerima koneksi
timeout /t 10

echo [6/6] Menjalankan Task Otomasi di dalam Container Laravel...
:: Menginstal dependensi vendor, menggenerasi enkripsi APP_KEY, dan menjalankan migrasi skema database
docker exec laravel_face_app composer install --no-interaction
docker exec laravel_face_app php artisan key:generate
docker exec laravel_face_app php artisan migrate --force

echo ------------------------------------------------------------------------------
echo INSTALASI & SETUP SELESAI!
echo Dashboard Web Laravel  : http://localhost:8080
echo Dokumentasi API FastAPI: http://localhost:8000/docs
echo ------------------------------------------------------------------------------
pause