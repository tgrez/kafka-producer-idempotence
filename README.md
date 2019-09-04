# Kafka idempotent producer

see: http://localhost:8000/posts/2019-09-04-simulate-network-failures.html

to run you will need:

* Linux
* x86_64
* docker installed and available as a unix socket at /var/run/docker.sock (should work with default install)
* current user added to the docker group
* Haskell's Stack installed
* librdkafka version 1.0 installed (use Confluent repository to get the latest version)
