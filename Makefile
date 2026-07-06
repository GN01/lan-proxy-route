include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-lan-proxy-route
PKG_VERSION:=0.2.0
PKG_RELEASE:=3
PKG_MAINTAINER:=Gin
PKG_LICENSE:=MIT

LUCI_TITLE:=LuCI support for LAN Proxy Route
LUCI_DESCRIPTION:=Route LAN clients foreign traffic to one LAN-side transparent proxy host using a China IPv4 GeoIP list.
LUCI_DEPENDS:=+luci-base +rpcd +ip-full +firewall4 +nftables +kmod-nft-core
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
