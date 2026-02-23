curl -sS -D headers.txt -o output.jpg \
  -X POST http://192.168.42.16:8000/ \
  -F "model=mosaic" \
  -F "image=@lenna.jpg;type=image/jpeg"

curl -sS -o output.jpg \
  -w "HTTP=%{http_code} content_type=%{content_type}\n" \
  -X POST http://192.168.42.16:8000/ \
  -F "model=mosaic" \
  -F "image=@lenna.jpg;type=image/jpeg"
