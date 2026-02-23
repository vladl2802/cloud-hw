FROM continuumio/miniconda3:22.11.1

RUN mkdir /app/
COPY . /app/
WORKDIR /app/

RUN apt-get update && apt-get install ffmpeg libsm6 libxext6  -y
RUN pip install -r requirements.txt

EXPOSE 8000
CMD ["gunicorn", "server:app"]
