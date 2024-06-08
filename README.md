# spark-with-glue-builder
Docker image that builds a patched Apache Spark v3.5.1 with AWS Glue support as metastore.

Although AWS Glue is advertised as Hive-compatible, Apache Spark cannot use it as a metastore out-of-the-box. This docker image builds a patched version of both Hive2 and Hive3, the AWS Glue Hive Metastore Client and finally Apache Spark using the patched clients.

The AWS Glue metastore is enabled by setting the following Spark config:
```
spark.hive.imetastoreclient.factory.class com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory
```

Please refer to this repository for further info: https://github.com/awslabs/aws-glue-data-catalog-client-for-apache-hive-metastore.

## Notes
The https://github.com/awslabs/aws-glue-data-catalog-client-for-apache-hive-metastore repository follows a branch-based approach in managing different versions and has renamed/deleted older branches in the past. To avoid future issues I have forked the original `branch-3.4.0` main branch of the repository into my GitHub account and created a specific tag which is referenced in this docker image.

This docker image also fixes the missing `conjars` maven repository, required when building the Glue Catalog Client.

Finally, this image builds Spark with `Spark-Connect` support. This repository includes a patch for Spark 3.5.1 that fixes a sporadic [`NoClassDefFoundError: InternalFutureFailureAccess`](https://issues.apache.org/jira/browse/SPARK-45201) that can be seen when building Spark from sources.

## Versions
The following package/language versions are currently used:
* Java 8
* Python 3.10.14
* Scala 2.12
* Maven 3.8.8
* Spark 3.5.1
* Hadoop 3.3.4
* Hive2 2.3.9
* Hive3 3.1.3
* AWS Java SDK 1.12.367
* Postgres 42.6.0
* Delta Lake 3.2.0

## Warning
This image is not intended to be run directly! The resulting image is going to be very large. You should use this image as source in a multi-stage docker build for creating your final Apache Spark images.


## Instructions
Follow these instructions to build the Docker image:

```bash
git clone https://github.com/sebastiandaberdaku/spark-with-glue-builder.git
cd spark-with-glue-builder
docker build -t sdaberdaku/spark-with-glue-builder:v3.5.1 . --network host
docker push sdaberdaku/spark-with-glue-builder:v3.5.1
```
