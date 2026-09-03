# vps_script
自用的脚本

## trojan_alpine.sh
> 快速安装trojan

```
wget -O trojan_install.sh https://raw.githubusercontent.com/fidcz/vps_script/refs/heads/main/trojan_install.sh && chmod +x trojan_install.sh && ./trojan_install.sh
```
或
```
curl -o trojan_install.sh https://raw.githubusercontent.com/fidcz/vps_script/refs/heads/main/trojan_install.sh && chmod +x trojan_install.sh && ./trojan_install.sh
```

## speed_brush.sh
> 自动刷流量  
### 首次安装  
```
curl -fsSL https://raw.githubusercontent.com/fidcz/vps_script/refs/heads/main/speed_brush.sh -o /usr/local/bin/speed_brush.sh && chmod +x /usr/local/bin/speed_brush.sh && /usr/local/bin/speed_brush.sh install
```
### 一键更新  
```
/usr/local/bin/speed_brush.sh uninstall && curl -fsSL https://raw.githubusercontent.com/fidcz/vps_script/main/speed_brush.sh -o /usr/local/bin/speed_brush.sh && chmod +x /usr/local/bin/speed_brush.sh && /usr/local/bin/speed_brush.sh install
```  
部署命令：./speed_brush.sh install（检查环境、安装依赖、自动写入 crontab）   
立即测试运行：./speed_brush.sh run   
查看实时运行日志：tail -f /tmp/speed_brush.log   
一键卸载定时任务：./speed_brush.sh uninstall   

## manage_dns_switch.sh  
> 自动切换主从dns ip   
```
curl -fsSL https://raw.githubusercontent.com/fidcz/vps_script/main/manage_dns_switch.sh -o manage_dns_switch.sh && chmod +x manage_dns_switch.sh && ./manage_dns_switch.sh
```
或  
```
wget -qO manage_dns_switch.sh https://raw.githubusercontent.com/fidcz/vps_script/main/manage_dns_switch.sh && chmod +x manage_dns_switch.sh && ./manage_dns_switch.sh
```
