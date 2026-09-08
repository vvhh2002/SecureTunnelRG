# 构建产物状态

当前产物是**开发用 CLI 验证包**，只能显示帮助和版本信息。它不会启动 Web、建立连接或修改网络，不能作为网关部署包使用。

Linux 交付架构目标为 x86_64 与 aarch64，运行系统基线为 Debian 13（trixie）。验证包不等于完整系统镜像，也不代表设备兼容性或自动恢复能力已经通过验证。

交付状态请查看：

- [项目说明](../README.md)
- [Docker 交付](../packaging/docker/README.md)
- [虚拟机镜像](../packaging/vm/README.md)
- [ISO 安装介质](../packaging/iso/README.md)
