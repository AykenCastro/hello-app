# Dockerfile

# 1. Base Image
FROM python:3.9-slim

# 2. Set working directory
WORKDIR /app

# 3. Install dependencies
COPY requirements.txt .
RUN pip install fastapi uvicorn

# 4. Copy app code
COPY . .

# 5. Expose port and run
EXPOSE 80
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]