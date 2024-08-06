#!/bin/bash

# ===== Create credential folder =========
CREDENTIAL="credential"
if [ ! -d "$CREDENTIAL" ]; then
    mkdir credential
    echo "admin@123" > $CREDENTIAL/password.txt
else
    rm -r "$CREDENTIAL"
    mkdir credential
    echo "admin@123" > $CREDENTIAL/password.txt
fi

# ===== Delete existing directory data ======
DIR="data"
if [ -d "$DIR" ]; then
    # If it exists, remove it along with its contents
    rm -r "$DIR"
    echo "Directory $DIR was removed."
else
    echo "Directory $DIR does not exist."
fi

# ======= Up Ceph container ========
docker compose up -d ceph-mon
sleep 2
docker compose up -d ceph-mgr
sleep 2
docker compose exec ceph-mon ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/ceph.keyring
sleep 2
docker compose up -d ceph-osd1 ceph-osd2 ceph-osd3
sleep 3
docker compose exec ceph-mon ceph auth get client.bootstrap-rgw -o /var/lib/ceph/bootstrap-rgw/ceph.keyring
sleep 2
docker compose up -d ceph-rgw
sleep 2
docker compose exec ceph-mon ceph auth get client.bootstrap-rbd -o /var/lib/ceph/bootstrap-rbd-mirror/ceph.keyring
sleep 2
docker compose up -d ceph-mds

sleep 2
# =========== Enable ceph dashbaod ========
docker compose exec ceph-mon ceph mgr module enable dashboard && \
docker compose exec ceph-mon ceph dashboard create-self-signed-cert && \
docker compose exec ceph-mon ceph config set mgr mgr/dashboard/server_addr ceph-mgr && \
docker compose exec ceph-mon ceph config set mgr mgr/dashboard/server_port 8443
sleep 1

# ================= Create Ceph admin user and S3 user ==============
docker compose exec ceph-mon ceph dashboard ac-user-create admin -i credential/password.txt administrator -o credential/ceph-admin.json && \
docker compose exec ceph-mon radosgw-admin user create --uid=test-user --display-name="Test User" --system > credential/s3-user.json

# ======================== Set RGW api
_accesskey=$(docker compose exec ceph-mon radosgw-admin user info --uid test-user | egrep -i access_key | cut -d ":" -f 2 | tr -d '", ') && \
_secretkey=$(docker compose exec ceph-mon radosgw-admin user info --uid test-user | egrep -i secret_key | cut -d ":" -f 2 | tr -d '", ') && \
echo "$_accesskey" > credential/access-key.txt
echo "$_secretkey" > credential/secret-key.txt
docker compose exec ceph-mon ceph dashboard set-rgw-api-access-key -i credential/access-key.txt
docker compose exec ceph-mon ceph dashboard set-rgw-api-secret-key -i credential/secret-key.txt
docker compose exec ceph-mon ceph dashboard set-rgw-api-ssl-verify False
docker compose exec ceph-mon ceph dashboard set-iscsi-api-ssl-verification false