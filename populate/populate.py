#!/usr/bin/python3

from urllib.parse import quote_plus as quote

import lorem
import random
import os
import ssl
import pymongo

host = os.environ['MONGO_HOSTNAME']
url = 'mongodb://{user}:{pw}@{hosts}/?replicaSet={rs}&authSource={auth_src}'.format(
    user=quote('spark'),
    pw=quote('password'),
    hosts=','.join([f'{host}:27018']),
    rs='rs01',
    auth_src='mongospark')
dbs = pymongo.MongoClient(
    url,
    ssl_ca_certs='/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt',
    ssl_cert_reqs=ssl.CERT_REQUIRED)['mongospark']

print(dbs.list_collection_names())

test_collection = dbs.test_collection
test_collection.drop()

loops_count = 1000
docs_in_loop_count = 10000
total_docs_count = loops_count * docs_in_loop_count
inserted_count = 0
for j in range(loops_count):
    docs = []
    for i in range(docs_in_loop_count):
        doc = {
            "num1": random.randint(0, 1000000),
            "num2": random.randint(0, 1000000),
            "num3": random.randint(0, 1000000),
            "num4": random.randint(0, 1000000),
            "num5": random.randint(0, 1000000),
            "str1": lorem.sentence(),
            "str2": lorem.sentence(),
            "str3": lorem.sentence(),
            "str4": lorem.sentence(),
            "str5": lorem.sentence(),
        }
        docs.append(doc)
    test_collection.insert_many(docs)
    inserted_count += len(docs)
    print(f'Inserted {inserted_count} documents out of {total_docs_count}', flush=True)

print(test_collection.count())
