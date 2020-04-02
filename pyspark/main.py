from urllib.parse import quote_plus as quote
from pyspark.sql import SparkSession
import os

host = os.environ['MONGO_HOSTNAME']
url = 'mongodb://{user}:{pw}@{hosts}/{db}.{collection}?replicaSet={rs}&authSource={auth_src}'.format(
    user=quote('spark'),
    pw=quote('password'),
    hosts=','.join([f'{host}:27018']),
    rs='rs01',
    db='mongospark',
    collection='test_collection',
    auth_src='mongospark')

spark = SparkSession \
    .builder \
    .appName("sparkmongo") \
    .config("spark.mongodb.input.uri", url) \
    .config("spark.mongodb.output.uri", url) \
    .config("spark.master", "local[*]") \
    .getOrCreate()

df = spark.read.format("mongo").load()
df.show(25, truncate=False)
