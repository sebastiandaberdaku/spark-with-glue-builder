# spark-with-glue-builder
Docker image that builds a patched Apache Spark v3.5.0 with AWS Glue support as metastore.

Although AWS Glue is advertised as Hive-compatible, Apache Spark cannot use it as a metastore out-of-the-box. This docker image builds a patched version of both Hive2 and Hive3, the AWS Glue Hive Metastore Client and finally Apache Spark using the patched clients.

The AWS Glue metastore is enabled by setting the following Spark config:
```
spark.hive.imetastoreclient.factory.class com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory
```

Please refer to this repository for further info: https://github.com/awslabs/aws-glue-data-catalog-client-for-apache-hive-metastore.

## Notes
The https://github.com/awslabs/aws-glue-data-catalog-client-for-apache-hive-metastore repository follows a branch-based approach in managing different versions and has renamed/deleted older branches in the past. To avoid future issues I have forked the original `branch-3.4.0` main branch of the repository into my GitHub account and created a specific tag which is referenced in this docker image.

This docker image also fixes the missing `conjars` maven repository, required when building the Glue Catalog Client.

Finally, this image buids Spark with `Spark-Connect` support. This repository includes a patch for Spark 3.5.0 that fixes a sporadic [`NoClassDefFoundError: InternalFutureFailureAccess`](https://issues.apache.org/jira/browse/SPARK-45201) that can be seen when building Spark from sources.

## Versions
The following package/language versions are currently used:
* Java 8
* Python 3.10.12
* Scala 2.12
* Maven 3.8.8
* Spark 3.5.0
* Hadoop 3.3.4
* Hive2 2.3.9
* Hive3 3.1.3
* AWS Java SDK 1.12.367

## Warning
This image is not intended to be run directly! The resulting image is going to be very large. You should use this image as source in a multi-stage docker build for creating your final Apache Spark images.


## Instructions
Follow these instructions to build the Docker image:

1. Clone this repository:
```bash
git clone https://github.com/sebastiandaberdaku/spark-with-glue-builder.git
```

2. Navigate to the repository:
```bash
cd spark-with-glue-builder
```

3. Build the Docker image:
```bash
docker build -t spark-with-glue-builder:v3.5.0 . --network host
```

## Image Details
### Base Image
The Dockerfile starts with the official Python 3.10 image (`python:3.10.12-bookworm`). I wanted to build Spark with PySpark support for Python 3.10, so I needed an image with both the JDK and Python 3.10. At the time of writing this Docker image, the latest Python version in synaptic package manager for Ubuntu/Debian was 3.9. Building Python from sources takes a long time, so I decided to start from a base image with Python 3.10 and simply install OpenJDK 8.

## Installed Packages
The following packages are installed during the build process:

### OpenJDK 8
`OpenJDK 8` is installed to support Spark and other Java-based components.

### Apache Maven
`Apache Maven` (version 3.8.8) is installed to manage the build lifecycle of the Glue Data Catalog Client, Apache Hive and Apache Spark.

### Glue Data Catalog Client
The Glue Data Catalog Client is downloaded, extracted, and patched to ensure compatibility with Hive and Spark.

### Apache Hive
Both Hive 2 and Hive 3 are downloaded, extracted, and patched. The build process includes Maven and resolves dependencies using a mirrored repository.

### Glue Data Catalog Client Build
With Hive patched and installed, the Glue Data Catalog Client is built. The build includes support for specific Hive and Spark versions.

### Apache Spark Build
Apache Spark sources (version 3.5.0) are downloaded, and Maven is configured for memory usage. A patch is applied to address a known issue, and Spark is built with support for various components, including Hive and Kubernetes.

### Additional Jars
Various JAR files required for Spark operation are downloaded and copied to the Spark distribution directory. These include the AWS Java SDK bundle, Hadoop AWS library, PostgreSQL library, Delta IO libraries, and other dependencies.

### Hadoop Native Libraries
Hadoop native libraries are downloaded and installed to support Hadoop operations.

## Important Notes
The Spark distribution directory is set to /opt/spark/dist.

To avoid a known issue (SPARK-45201), the spark-connect-common JAR is deleted from the Spark jars directory.

The Glue Data Catalog Spark Client JAR is copied to the Spark jars directory.

Additional JAR files are downloaded directly to the Docker image to avoid downloading them during Spark startup.

Hadoop native libraries are installed to support Hadoop operations within Spark.

## Customization
You can customize this Dockerfile to suit your specific requirements by modifying the relevant sections or adding/removing dependencies based on your Spark application needs.
