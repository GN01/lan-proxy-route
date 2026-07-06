include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-lan-proxy-route
PKG_VERSION:=0.1.0
PKG_RELEASE:=3
PKG_MAINTAINER:=Gin
PKG_LICENSE:=MIT

LUCI_TITLE:=LuCI support for LAN Proxy Route
LUCI_DESCRIPTION:=Route selected LAN clients foreign traffic to one LAN-side transparent proxy host.
LUCI_DEPENDS:=+luci-base +rpcd +dnsmasq-full +ip-full +firewall4 +nftables +kmod-nft-core
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
