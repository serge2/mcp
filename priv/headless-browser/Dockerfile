# Используем рабочий образ с Python 3.10
FROM mcr.microsoft.com/playwright/python:v1.55.0-noble

# Устанавливаем Playwright для Python, FastAPI и Uvicorn
RUN pip install --no-cache-dir playwright fastapi uvicorn

# Устанавливаем браузеры через Python
RUN python -m playwright install --with-deps

# Рабочая директория
WORKDIR /app

# Копируем сервис
COPY service.py /app/service.py

# Открываем порт
EXPOSE 8000

# Запуск FastAPI через Uvicorn
CMD ["uvicorn", "service:app", "--host", "0.0.0.0", "--port", "8000"]
