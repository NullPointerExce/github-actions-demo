# Build stage
FROM python:3.9-slim AS builder

WORKDIR /app

COPY requirements.txt .
# 这在构建过程中在容器中运行一个命令。它安装我们的 Python 依赖项。这创建了一个新层，其中包含所有已安装的软件包。
RUN pip install --user --no-cache-dir -r requirements.txt

# Final stage
FROM python:3.9-slim

# Create a non-root user
# 这会在容器中创建一个名为 appuser 的新用户。以非 root 用户身份运行应用程序是一种安全最佳实践，因为它限制了应用程序被攻陷时可能造成的潜在损害。-m 标志会为该用户创建主目录。
RUN useradd -m appuser

# Install curl for healthcheck
# 这会安装 curl 包，它是使我们的 HEALTHCHECK 指令正常工作所必需的。我们还会清理 apt 缓存以减小镜像大小。
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# 这为后续指令设置了工作目录。它不会创建新层，但会影响后续指令的行为。
WORKDIR /app

# Dynamically determine Python version and site-packages path
# 这组命令会动态确定容器内的 Python 版本，并为 appuser 创建正确的 site-packages 目录。它还会为用户的本地目录设置正确的权限。
RUN PYTHON_VERSION=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")') && \
    SITE_PACKAGES_PATH="/home/appuser/.local/lib/python${PYTHON_VERSION}/site-packages" && \
    mkdir -p "${SITE_PACKAGES_PATH}" && \
    chown -R appuser:appuser /home/appuser/.local

# Copy site-packages and binaries using the variable
# 此指令将安装的 Python 包从 builder 阶段复制到最终镜像中动态确定的 site-packages 路径，确保包放置在 appuser 可以使用的正确位置。
COPY --from=builder /root/.local/lib/python3.9/site-packages "${SITE_PACKAGES_PATH}"
# 这会将 pip 安装的可执行脚本（例如 Flask 的命令行接口，如果有的话）从 builder 阶段复制到 appuser 的本地 bin 目录。
COPY --from=builder /root/.local/bin /home/appuser/.local/bin
COPY app.py .

ENV PATH=/home/appuser/.local/bin:$PATH
# 这设置了一个环境变量。环境变量不会创建新层，但它们存储在镜像元数据中。
ENV ENVIRONMENT=production

# Set the user to run the application
USER appuser

# Use ENTRYPOINT with CMD
# 当一起使用时，ENTRYPOINT 定义了容器的主要可执行文件（在本例中为 python），而 CMD 为该可执行文件提供了默认参数（app.py）。这种模式允许灵活性：用户可以默认运行容器并执行 app.py，或者他们可以覆盖 CMD 来运行其他 Python 脚本或命令。
ENTRYPOINT ["python"]
CMD ["app.py"]

# 这实际上只是一种文档形式。它告诉 Docker 容器将在运行时在此端口上监听，但实际上不会发布该端口。它不会创建层。
EXPOSE 5000

# 此指令配置容器的健康检查。Docker 将定期执行指定的命令（curl -f http://localhost:5000/）以确定容器是否健康。--interval=30s 和 --timeout=3s 标志分别设置检查间隔和超时时间。如果 curl 命令失败（返回非零退出代码），则认为容器不健康。
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:5000/ || exit 1

# 这定义了一个名为 BUILD_VERSION 的构建参数（build argument）。构建参数允许你在构建时向 Docker 镜像传递值。
ARG BUILD_VERSION
# 这些将元数据添加到镜像中。与 ENV 指令一样，它们不会创建新层，但存储在镜像元数据中。
LABEL maintainer="Your Name <your.email@example.com>"
# 这会在 Docker 镜像上设置一个名为 version 的标签（label）。它使用 BUILD_VERSION 构建参数。如果在构建过程中提供了 BUILD_VERSION，则使用其值；否则，它默认为 1.0（使用 :- 默认值语法）。
LABEL version="${BUILD_VERSION:-1.0}"
LABEL description="Flask app demo with advanced Dockerfile techniques"