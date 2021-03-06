---
categories: Code
date: 2016-07-08T00:00:00Z
tags:
- Node.js
- JavaScript
title: NodeBB 升级迁移总结
toc: true
url: /2016/07/08/nodebb-upgrade/
---

[青云用户社区](https://community.qingcloud.com/)使用了开源的 NodeBB 论坛，部署之初使用`0.7`版本，因为没有跟随官方进度进行更新，导致论坛版本长期停滞。一方面无法享受到官方的BUG Fix，另一方面也无法使用很多业务需求的插件。思量再三后决定对社区进行升级迁移，不在原论坛直接升级，而是部署一套新的环境，将原有的数据全部导出。

<!--more-->

# 可行性分析

## NodeBB 升级路径

NodeBB 自0.3版本后就提供了一套独特升级路径，主要有以下几个要点：

- NodeBB采用语义化版本号：`x.y.z`
- 对`z`版本号的变动，可以直接升级
- 只有当`z`版本号已经是`x.y`版本下的最新版本，才能升级到`x.y+1`

## 数据迁移

NodeBB在部署的时候就使用了青云平台上的 Redis 缓存和负载均衡器。这样迁移的问题就会变的简单很多，我只需要将 NodeBB 路径下的`public/uploads`资源进行打包即可，Redis 缓存和负载均衡器都可以直接使用。

# 迁移步骤

## 迁移 NodeBB

建议在一个新的环境里面创建迁移环境。

### Node 版本

同样建议使用 `nvm` 来管理版本，避免其他应用对NodeBB环境产生干扰。

```
nvm install stable
nvm use stable
```

如果不想每一次退出shell后都要执行`nvm use stable`，可以手动设置默认版本：

```
nvm alias default stable
```

### NodeBB 版本

首先下载跟生产环境一致的NodeBB版本：

```
git clone -b v0.7.x 
```

然后使用跟生产环境一致的`config.json`，NoedBB升级工具会自动更新`package.json`，所以无需修改。

然后运行`./nodebb upgrade`以升级数据结构和依赖并打上所有的补丁。

运行完毕后切换到更高版本的分支：

```
git fetch
git checkout v0.8.x
```

同样运行`./nodebb upgrade`，以此类推，直至升级到官方最新版本。

## 迁移数据

正如之前所说的，Redis已经被直接升级到最新版本，接下来只需要将用户上传的数据导出即可。

在生产环境中执行如下命令：

```
cd /path/to/nodebb/public
tar -cvf nodebb_assets_backup.tar.gz ./upload
```

切换到迁移环境后执行：

```
cd /path/to/nodebb/public
tar -xvf nodebb_assets_backup.tar.gz
```

## 注意事项

- 目前NodeBB不支持降级操作，如果担心破坏生产环境，可以在生成一个 Redis 的备份并重新创建资源，不要对原数据库进行操作。
- 由于 Redis 中会保存对原论坛的主题和插件等配置，在迁移到新版本后，有很大可能会产生错误，可以执行`./nodebb reset -a`以清除所有主题和插件配置。确认 NodeBB 运行正常后再逐个启用即可。
- 在升级时候会因为Node.js版本的问题导致某些依赖无法安装，建议可以使用`0.12`版本进行升级，升级成功后再切换到更新的版本上重新进行`npm install --production`

# 感悟

## NodeBB的升级路线设计

这次升级迁移其实经历很久的论证过程。
一开始简单地尝试一下之后认定无法直接进行升级就产生了一些畏难情绪，心里想着不如就让它这样，反正现在线上跑得也挺好的，没有出什么太大的问题。而后种种需求的提出让我有些招架不住了，现有的落后版本缺少很多API和现有的插件，自行开发和维护的成本非唱高。这也是我有一段时间觉得开源在实际应用中并不是那么美好的原因。
等到我真的沉下心来仔细研究官方的文档，才发现 NodeBB 看似鬼畜坑爹的升级路线设计其实也有着其优雅之处。数据库的结构可以随之版本同步更新，这样可以避免早期数据库结构设计不合理带来的种种弊端，并防止产生版本之间的Breaking Change。抛开API层面的兼容性不谈，NodeBB可以做到我直接使用原来的 Redis 从 `0.7.0` 一路升级到 `1.0.4`，还能保证我的数据没有出现任何丢失，就冲着这一点，我觉得这个升级路线的设计是有价值的。
当然，路线是好的，但是在具体实现升级功能的时候还有待商榷之处：不难发现升级过程中有很大一部分的重复操作，其实这些都是可以避免的。每一个`x.y`版本号之间的更新操作其实都是一致的，完全可以通过脚本实现。

## 应用部署的灵活性

上线任何应用之前都应该考虑其架构的扩展性和迁移能力。
很多时候，部署一套应用的目的根本就不是为了去使用他，只是单纯的部署一个玩一玩而已。在这样的心态下，总会干出这样的事情：在一个20G的主机上跑ownCloud；在一个主机上同时跑wordpress，nginx和mysql等应用。当然，这样做并没有什么问题，毕竟是自己的Server，哪怕天天 `rm -rf /`都是OK的。
但是如果是一套需要给别人用的应用，部署时的扩展性和迁移能力就必须考虑在内。这其实是两个很实在的问题：服务器空间耗尽，性能跟不上怎么办？服务器挂了，如何保全自己的数据？自己设计这样一套系统很麻烦，但是如果是在青云上就不一样了。我最喜欢青云的一点就是，青云几乎所有的资源都是可以动态伸缩和扩展的。带宽受限制了，直接扩大；服务器性能不够了，加核心加内存；单个服务器支撑不住了，批量生成十个并使用负载均衡器进行负载均衡操作；想要测试某个最新的特性，直接从线上创建一个Snapshot并生成资源进行测试。
在本次迁移的过程中，我们就可以看出来，我们可以直接使用 Redis 进行升级，而不是手动导出数据库备份再执行导入操作。同样地，我们也不需要再重新配置一遍 Nginx ，只需要再创建一个负载均衡器即可。

# 更新日志

- 2016年07月08日 首次发布
- 2016年07月15日 青云社区成功上线
