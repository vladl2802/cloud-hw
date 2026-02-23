import multiprocessing

bind = "0.0.0.0:8000"
workers = 1
worker_class = 'gthread'
threads = 2 * (1 + multiprocessing.cpu_count())
