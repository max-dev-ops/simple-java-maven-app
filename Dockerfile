FROM maven:3.9-amazoncorretto-17 AS build
          # Intentionally insecure practice - running as root
        #   USER root
          # Intentional vulnerability - hardcoded credentials
        #   ENV DB_PASSWORD=supersecretpassword
          WORKDIR /app
          COPY pom.xml .
          RUN mvn dependency:go-offline
          COPY src ./src
          # Using 'package' as 'verify' might not create the final JAR in target/ needed below
          RUN mvn clean package -DskipTests

          # Extract layers if Spring Boot, otherwise copy JAR
          RUN mkdir -p extracted && \
              if jar -tf target/*.jar | grep -q "BOOT-INF/layers.idx"; then \
                echo "Spring Boot layered JAR detected..."; \
                java -Djarmode=layertools -jar target/*.jar extract --destination extracted; \
              else \
                echo "Regular JAR detected..."; \
                mkdir -p extracted/application; \
                cp target/*.jar extracted/application/; \
              fi

          FROM eclipse-temurin:17-jre-alpine
          WORKDIR /app
        #   LABEL org.opencontainers.image.source=https://github.com/${{ github.repository }}
          RUN addgroup --system javauser && adduser --system --ingroup javauser javauser
          COPY --from=build --chown=javauser:javauser /app/extracted/ ./
          USER javauser
          ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
          EXPOSE 8080
          ENTRYPOINT ["sh", "-c", "if [ -f 'org/springframework/boot/loader/JarLauncher.class' ]; then java $JAVA_OPTS org.springframework.boot.loader.JarLauncher; elif [ -d 'application' ]; then java $JAVA_OPTS -jar application/*.jar; else java $JAVA_OPTS -jar *.jar; fi"]