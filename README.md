Данный репозиторий содержит пример, как можно на платформе Яндекс.Облака настоить связку Spark + MongoDB. 

Скачиваем данный репозиторий:

```bash
git clone https://github.com/vbelov/mongospark.git
cd mongospark
```

С помощью terraform'а создаем [Yandex Managed Service for MongoDB](https://cloud.yandex.ru/docs/managed-mongodb/), кластер [Yandex Data Proc](https://cloud.yandex.ru/docs/data-proc/), а также бастионный хост, через который можно будет получить доступ к ресурсам, находящимся в приватной сети.

```bash
cd terraform
terraform init
terraform apply
```

Если terraform не установлен, то рекомендуется сделать это по инструкции https://learn.hashicorp.com/terraform/getting-started/install.html.

Далее через [веб консоль управления](https://console.cloud.yandex.ru) рекомендуется включить NAT для созданной терраформом подсети mongospark.

Добавляем пользователю необходимые разрешения для записи в БД (к сожалению, в настощий момент terraform провайдер не позволяет этого сделать):

```bash
(yc managed-mongodb user revoke-permission --database=mongospark spark --cluster-name=mongospark || true) && yc managed-mongodb user grant-permission --database=mongospark --role=readWrite spark --cluster-name=mongospark
```

Далее устанавливаем необходимые переменные окружения:

```bash
export GATEWAY_IP=$(terraform output | grep gateway_ip | awk '{ print $3; }') && echo "Gateway: $GATEWAY_IP"
export DATAPROC_MASTER_HOSTNAME=$(yc dataproc cluster list-hosts mongospark | grep MASTERNODE | awk '{ print $2; }') && echo "DataProc master hostname: $DATAPROC_MASTER_HOSTNAME"
export MONGO_HOSTNAME=$(yc managed-mongodb hosts list --cluster-name=mongospark | grep PRIMARY | awk '{ print $2; }') && echo "Mongo hostname: $MONGO_HOSTNAME"
```

Устанавливаем сертификат для подключения к MongoDB:

```bash
ssh -t ubuntu@$GATEWAY_IP "sudo mkdir -p /usr/local/share/ca-certificates/Yandex && sudo wget "https://storage.yandexcloud.net/cloud-certs/CA.pem" -O /usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt"
```

Копируем на сервера код:

```bash
cd ..
rsync -r --exclude 'venv' ./ ubuntu@$GATEWAY_IP:~/mongospark/
ssh -A ubuntu@$GATEWAY_IP "ssh-keyscan $DATAPROC_MASTER_HOSTNAME >> ~/.ssh/known_hosts"
ssh -A ubuntu@$GATEWAY_IP "scp ~/mongospark/pyspark/main.py root@$DATAPROC_MASTER_HOSTNAME:~/"
```

Наполняем БД сгенерированными данными:

```bash
ssh -t ubuntu@$GATEWAY_IP "cd mongospark/populate/ && sudo apt install -y python3-venv && python3 -m venv venv && ./venv/bin/pip install -r requirements.txt && MONGO_HOSTNAME=$MONGO_HOSTNAME ./venv/bin/python populate.py"
```

Установим mongo-spark-connector на DataProc кластер. Это может занять некоторое время. Кроме того, для успешного выполнения данного шага DataProc кластер должен иметь доступ в интернет, а для этого необходимо включить NAT на подсети, в которой он находится. Необходимо дождаться, когда загрузится интерактивная консоль, затем из нее можно выйти:

```bash
ssh -t -A ubuntu@$GATEWAY_IP "ssh -t root@$DATAPROC_MASTER_HOSTNAME time MONGO_HOSTNAME=$MONGO_HOSTNAME spark-shell --packages org.mongodb.spark:mongo-spark-connector_2.11:2.4.1"
```

Запускаем на мастерноде DataProc кластера, тестовую pyspark задачу и замеряем время ее выполнения:

```bash
ssh -t -A ubuntu@$GATEWAY_IP "ssh -t root@$DATAPROC_MASTER_HOSTNAME time MONGO_HOSTNAME=$MONGO_HOSTNAME spark-submit --packages org.mongodb.spark:mongo-spark-connector_2.11:2.4.1 main.py"
```
