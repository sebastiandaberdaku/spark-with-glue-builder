# I want to build Spark with PySpark support for Python 3.10, so I need a docker image with both Python and Java.
# It is faster to start from an image with Python and install the JDK later. 
FROM python:3.10.14-bookworm

# Install packages
RUN echo "deb http://ftp.de.debian.org/debian sid main" >> /etc/apt/sources.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends openjdk-8-jdk wget patch; \
    rm -rf /var/lib/apt/lists/*

# Install maven
ARG MAVEN_VERSION=3.8.8
RUN wget --quiet -O /opt/maven.tar.gz "https://apache.org/dyn/closer.lua/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz?action=download"; \
    mkdir -p /opt/maven; \
    tar zxf /opt/maven.tar.gz --strip-components=1 --directory=/opt/maven; \
    rm /opt/maven.tar.gz

ENV MAVEN_HOME=/opt/maven
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
ENV PATH=$PATH:${MAVEN_HOME}/bin

WORKDIR /opt
# Download and extract the Glue Data Catalog Client
ARG SPARK_VERSION=3.5.1
RUN wget --quiet -O /opt/glue.tar.gz "https://github.com/sebastiandaberdaku/aws-glue-data-catalog-client-for-apache-hive-metastore/archive/refs/tags/v${SPARK_VERSION}.tar.gz"; \
    mkdir -p /opt/glue; \
    tar zxf /opt/glue.tar.gz --strip-components=1 --directory=/opt/glue; \
    rm /opt/glue.tar.gz

## Patching Apache Hive and Installing It Locally
# Download and extract Apache Hive2 sources
ARG HIVE2_VERSION=2.3.9
RUN wget --quiet -O /opt/hive2.tar.gz "https://github.com/apache/hive/archive/rel/release-${HIVE2_VERSION}.tar.gz"; \
    mkdir -p /opt/hive2; \
    tar zxf /opt/hive2.tar.gz --strip-components=1 --directory=/opt/hive2; \
    rm /opt/hive2.tar.gz
# Add the 2.3 version patch file
COPY ./HIVE-12679.branch-2.3.patch /opt/hive2
# conjars repository is dead, mirroring to another repo to download jars
COPY ./.mvn/ /opt/hive2/.mvn/
RUN cd /opt/hive2; \
    patch -p0 <HIVE-12679.branch-2.3.patch; \
    mvn -T $(nproc) clean install -DskipTests

# Download and extract Apache Hive3 sources
ARG HIVE3_VERSION=3.1.3
RUN wget --quiet -O /opt/hive3.tar.gz "https://github.com/apache/hive/archive/rel/release-${HIVE3_VERSION}.tar.gz"; \
    mkdir -p /opt/hive3; \
    tar zxf /opt/hive3.tar.gz --strip-components=1 --directory=/opt/hive3; \
    rm /opt/hive3.tar.gz
# conjars repository is dead, mirroring to another repo to download jars
COPY ./.mvn/ /opt/hive3/.mvn/
# Continue with patching the 3.1 branch:
RUN cp /opt/glue/branch_3.1.patch /opt/hive3; \
    cd /opt/hive3; \
    patch -p1 --merge <branch_3.1.patch; \
    mvn -T $(nproc) clean install -DskipTests

## Building the Glue Data Catalog Client
# Now with Hive patched and installed, build the glue client
# Adding the .mvn folder content fixes the missing conjars repository.
COPY ./.mvn/ /opt/glue/.mvn/
# All clients must be built from the root directory of the AWS Glue Data Catalog Client repository.
# This will build both the Hive and Spark clients and necessary dependencies.
ARG HADOOP_VERSION=3.3.4
RUN cd /opt/glue; \
    mvn -T $(nproc) clean install \
    -DskipTests \
    -Dspark-hive.version="${HIVE2_VERSION}" \
    -Dhive3.version="${HIVE3_VERSION}" \
    -Dhadoop.version="${HADOOP_VERSION}"

## Build Spark
# Fetch the Spark sources
RUN wget --quiet -O /opt/spark.tar.gz "https://github.com/apache/spark/archive/refs/tags/v${SPARK_VERSION}.tar.gz"; \
    mkdir -p /opt/spark; \
    tar zxf /opt/spark.tar.gz --strip-components=1 --directory=/opt/spark; \
    rm /opt/spark.tar.gz

# Setting up Maven's Memory Usage
ENV MAKEFLAGS="-j$(nproc)"
ENV MAVEN_OPTS="-Xss64m -Xmx2g -XX:ReservedCodeCacheSize=1g"
# Patch (see: https://issues.apache.org/jira/browse/SPARK-45201) and build a runnable Spark distribution
COPY "./spark-${SPARK_VERSION}.patch" /opt/spark/
ARG SCALA_VERSION=2.12
RUN cd /opt/spark; \
    patch -p1 <"spark-${SPARK_VERSION}.patch"; \
    ./dev/make-distribution.sh \
      --name spark \
      --pip \
      -P"scala-${SCALA_VERSION}" \
      -Pconnect \
      -Pkubernetes \
      -Phive \
      -Phive-thriftserver \
      -P"hadoop-${HADOOP_VERSION%%.*}" \
      -Dhadoop.version="${HADOOP_VERSION}" \
      -Dhive.version="${HIVE2_VERSION}" \
      -Dhive23.version="${HIVE2_VERSION}" \
      -Dhive.version.short="${HIVE2_VERSION%.*}"

ARG SPARK_DIST_DIR=/opt/spark/dist

# IMPORTANT! We must delete the spark-connect-commom jar from the jars directory!
# see: https://issues.apache.org/jira/browse/SPARK-45201
RUN rm "${SPARK_DIST_DIR}/jars/spark-connect-common_${SCALA_VERSION}-${SPARK_VERSION}.jar"

# Copy the glue client jars to the spark jars directory
# We are only interested in the AWS Glue Spark Client
RUN cp "/opt/glue/aws-glue-datacatalog-spark-client/target/aws-glue-datacatalog-spark-client-${SPARK_VERSION}.jar" "${SPARK_DIST_DIR}/jars/"

# The following steps are optional
# I am downloading these jars directly to the docker image in order to avoid having to download them when Spark starts up.

# Download the other jars
# AWS Java SDK bundle library
ARG AWS_JAVA_SDK_VERSION=1.12.262
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_JAVA_SDK_VERSION}/aws-java-sdk-bundle-${AWS_JAVA_SDK_VERSION}.jar"
# Hadoop AWS library
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar"
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/org/wildfly/openssl/wildfly-openssl/1.0.7.Final/wildfly-openssl-1.0.7.Final.jar"
# PostgreSQL library
ARG POSTGRES_VERSION=42.6.0
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/org/postgresql/postgresql/${POSTGRES_VERSION}/postgresql-${POSTGRES_VERSION}.jar"
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/org/checkerframework/checker-qual/3.31.0/checker-qual-3.31.0.jar"
# Delta IO libraries
ARG DELTA_VERSION=3.2.0
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/io/delta/delta-spark_${SCALA_VERSION}/${DELTA_VERSION}/delta-spark_${SCALA_VERSION}-${DELTA_VERSION}.jar"
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/4.9.3/antlr4-runtime-4.9.3.jar"
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/io/delta/delta-storage/${DELTA_VERSION}/delta-storage-${DELTA_VERSION}.jar"
RUN wget --quiet -P "${SPARK_DIST_DIR}/jars/" "https://repo1.maven.org/maven2/io/delta/delta-storage-s3-dynamodb/${DELTA_VERSION}/delta-storage-s3-dynamodb-${DELTA_VERSION}.jar"

# Download and install Hadoop native libraries
ARG HADOOP_HOME=/opt/hadoop
RUN wget "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" -O /opt/hadoop.tar.gz; \
    mkdir -p ${HADOOP_HOME}; \
    tar zxf /opt/hadoop.tar.gz --strip-components=1 --directory="${HADOOP_HOME}"; \
    rm /opt/hadoop.tar.gz