FROM maven:3.9-amazoncorretto-17 AS build
          WORKDIR /app

          # Copy only pom.xml first to leverage Docker cache layers
          COPY pom.xml .
          RUN mvn dependency:go-offline

          # Copy source and build
          COPY src ./src
          RUN mvn clean package -DskipTests

          # Try to detect if this is a Spring Boot app with layering support
          # This creates a conditional build pipeline that works with both
          # regular Java apps and Spring Boot apps with layertools
          RUN mkdir -p extracted && \
              if jar -tf target/*.jar | grep -q "BOOT-INF/layers.idx"; then \
                echo "Spring Boot layered JAR detected, extracting layers..."; \
                java -Djarmode=layertools -jar target/*.jar extract --destination extracted; \
              else \
                echo "Regular JAR detected, using simple copy..."; \
                mkdir -p extracted/application; \
                cp target/*.jar extracted/application/; \
              fi

          FROM eclipse-temurin:17-jre-alpine
          WORKDIR /app

          LABEL org.opencontainers.image.description="Optimized Java application container"

          # Security: Create non-root user for running the application
          RUN addgroup --system javauser && adduser --system --ingroup javauser javauser

          # Try to copy layers if available, fall back to regular JAR if not
          # This supports both Spring Boot layered apps and regular Java apps
          COPY --from=build --chown=javauser:javauser /app/extracted/ ./

          # Set appropriate permissions
          RUN chmod -R u=rX,g=rX /app
          USER javauser

          # Alpine optimization: Remove unnecessary files to keep image small
          # Container ready configuration
          ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

          EXPOSE 8080

          # Dynamic entrypoint that works for both Spring Boot and standard Java apps
          ENTRYPOINT ["sh", "-c", "if [ -f 'org/springframework/boot/loader/JarLauncher.class' ]; then java $JAVA_OPTS org.springframework.boot.loader.JarLauncher; elif [ -d 'application' ]; then java $JAVA_OPTS -jar application/*.jar; else java $JAVA_OPTS -jar *.jar; fi"]