# Neural Style Transfer with OpenCV

A simplified version of the code from [this repo](https://github.com/iArunava/Neural-Style-Transfer-with-OpenCV) 
that performs style transfer by applying a pretrained model to the input image.

Dependencies: see `requirements.txt`.

Usage example:

```
python app/style-transfer.py -i examples/lenna.jpg -m app/models/mosaic.t7 -o examples/lenna-mosaic.jpg
```

# Flask app
Run app:
```
gunicorn server:app
```
Or from container:
```
docker build -t fsta . && docker run -p 8000:8000 -it fsta
```
