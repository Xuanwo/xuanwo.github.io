---
categories: Code
date: 2018-09-05T09:00:00Z
tags:
- Golang
- QingStor
- QingCloud
series: "Self-made Wheels"
title: qscamel —— 数据迁移工具
url: /2018/09/05/qscamel-intro/
---

qscamel 是一个用于在不同的端点 (Endpoint) 中高效迁移数据的工具。

<!--more-->

作为一个面向用户的数据迁移工具，它必须要满足如下要求：

- 不丢数据：这是一个数据迁移工具最基本的要求。不能多，不能少，不能错，要支持校验和修复。
- 好用：作为一个给用户使用的工具，它需要足够好用。有完善的日志，不会无故退出，网络波动时能够自动重试，部署 & 配置容易，能够支持断点续传，无需人工干预。
- 高效：数据迁移通常都会有大量的文件传输，工具必须能够高效的使用服务器资源和带宽，节省用户执行迁移所需要的时间。
- 扩展性强：数据迁移所需要的场景千奇百怪，工具必须能够扩展并支持大多数用户的场景，减少后续开发和维护的成本。

qscamel 正是在这些要求下诞生的产物，它或许还不是那么完美，但是已经可用。目前已经圆满完成了很多数据迁移任务，任务涉及文件数量上亿，文件大小达数百 TB 。这篇文章将会介绍 qscamel 设计，实现和开发过程中的一些小故事，希望能够简单的告诉大家在 QingCloud 我们是如何做产品的，以及为我们的 HR 小姐姐提前打一个招聘的广告:)

## 设计

qscamel 只有一个功能，但是为了把这个功能做好，它需要在各个层面上都有一个比较良好的设计。

### 用户交互

一个好的命令行工具应该如何跟用户交互呢？嗯，抛开使用场景谈好坏都是耍流氓，那我重新组织一下语言：一个给**终端用户**使用的**数据迁移**工具应该如何跟用户交互？这里有两个关键点：第一，终端用户意味着使用者不是像我这样的高级用户，他们大多数只有一点甚至是没有使用命令行程序的经验，他们能读一些中文的文档，他们无法自行处理或者理解程序返回的错误，他们记不住程序的参数；第二，数据迁移意味着这个程序可能会运行很长的时间，用户不会一直在边上守着，同时这个程序用户可能不会频繁使用。分析到这里，我们已经能够大概的想象到这个工具应该是什么样子了：

- 命令要少，参数要少
- 学习成本要低，迁移成本要低（换个任务类型不需要重新学习配置方法）
- 任务启动后无需用户介入

除了需要考虑用户体验之外，我们还需要考虑开发体验。一个数据迁移工具，必然需要能够处理多种不同的数据来源和迁移目标，以及他们各自不一样的复杂参数。如果按照传统开发命令行工具的习惯，每个不同的端点都使用参数来进行配置，那光是参数解析和处理就要写很久。

因此，qscamel 最终的交互设计稿是这样的：

```bash
$ qscamel run task-name [ -t /path/to/task/file ]
$ qscamel delete task-name
$ qscamel status
$ qscamel clean
$ qscamel version
```

与之相对比的是 v1 版本的 qscamel：

```bash
$ qscamel -t s3 -s s3-bucket-name -z us-east-1 -a "S3ACCESSKEYID" -S "S3SECRETACCESSKEY" -b qingstor-bucket-name -d "migrate 05"
```

同时，我们将复杂的任务配置拆分为三块：qscamel 本身的配置，任务的配置，端点的配置，并将他们分成两个文件：qscamel 本身的配置独立的存储在一个全局的配置文件中，任务和端点的配置放在一个我们定义好的任务配置当中。

全局的配置文件形如：

```yaml
concurrency: 0
log_level: info
pid_file: ~/.qscamel/qscamel.pid
log_file: ~/.qscamel/qscamel.log
database_file: ~/.qscamel/db
```

而任务的配置文件格式同样是精心设计过的：

```yaml
type: copy

source:
  type: fs
  path: /path/to/source

destination:
  type: qingstor
  path: /path/to/destination
  options:
    bucket_name: example_bucket
    access_key_id: example_access_key_id
    secret_access_key: example_secret_access_key

ignore_existing: last_modified
```

每个任务会由 `type`，`source`，`destination` 和任务相关的配置组成。其中 `source` 和 `destination` 配置格式一样，都由 `type`，`path` 和 `options` 组成。藉由这样的设计，我们希望能够在易用性和扩展性上取得一个统一。用户可以很快的知道自己需要配置的东西，并且能够忽略无关参数的干扰，比如说我要配置从 fs 迁移到 qingstor，我就不需要了解 s3 的配置参数。还有一个好处是，用户只要写一次配置文件，他就能够将其应用到别的场景：比如说进行 `delete` 而不是 `copy`，比如说从 `s3` 迁移到 `qingstor` 而不是从 `fs`。使用一个格式规范的配置文件对于开发来说更是意义重大，开发者不再需要去维护一份晦涩难懂的参数列表，能够用更加一致的方法来处理所有的端点。

下面我们同样用 v1 版本的 qscamel 来做对比：

他首先有一个参数列表

```
| short | full             | type   | required |
|-------|------------------|--------|----------|
| -z    | --src-zone       | string | N        |
| -a    | --src-access-key | string | N        |
| -S    | --src-secret-key | string | N        |
```

然后根据不同的 Source 还需要选择不同参数的组合：

```
| platform | require --src-zone | require --src-access-key | require --src-secret-key |
|----------|--------------------|--------------------------|--------------------------|
| s3       | Y                  | Y                        | Y                        |
| qiniu    | N                  | Y                        | Y                        |
| aliyun   | Y                  | Y                        | Y                        |
| upyun    | Y                  | Y                        | Y                        |
| qingstor | Y                  | Y                        | Y                        |
```

这还没有考虑到不同 Source 各自不同的参数配置呐 (๑•̀ㅂ•́) ✧

### 整体流程

上面我们说到 qscamel 需要做到`任务启动后无需用户介入`，接下来就聊一聊 qscamel 整体的任务流程是怎么样的。

启动任务，检查任务文件的内容是否正确，初始化 Source 和 Destination 之后，qscamel 会不断的进行如下循环：

- 启动一个 listWorker 不断的从 Source 中遍历 Object
  - 如果遍历失败将会自动重试
  - 如果遍历结束将会关闭任务队列，不再追加新的任务
  - 如果获取到新的 Object，则首先会将其保存到数据库，然后再添加到任务队列
- 启动指定数量的 migrateWorker 不断的从任务队列中获取任务
  - 如果任务执行失败则会重试三次，每次重试的间隔会变长，若还是失败则会跳过
  - 如果任务执行成功则会从数据库中删除该任务
- 等到任务队列中所有的任务均已执行完毕，qscamel 将会遍历数据库
  - 如果数据库中没有未执行完毕的任务，则该迁移任务已成功，退出
  - 如果数据库中还有未执行完毕的任务，则重新开始上述流程

> 不难发现，如果因为某些原因，某个 Object 一直在重试，那么 qscamel 将永远不会退出，并一直在输出报错的日志。这个在设计中是作为一个产品特性考虑的，但是根据实际的用户反馈，他们更希望程序能够将这些一直失败的任务在最后的时候统一输出，因此之后重新考虑一下，看如何交互更好。

### 分段上传

分段上传并不是什么新奇玩意儿，但是如果要做一个不依赖服务器状态，支持并发上传多个块，支持从断点恢复而且还好看的分段上传，却实打实的花了我整整一个下午的时间。不依赖服务器状态是说我们需要在本地存储分块上传的完成情况，而不是通过调用服务器端的 API 来获取，这样可以减少很多轮查询的开销；支持并发上传多个块就是字面意思，我们需要在分块的级别上做到并发，而不是单线程跑；支持从断点恢复是说已经上传的块需要跳过，只上传还没有完成的块。之前 qscamel 使用的是 qingstor-sdk-go 提供的一个比较简陋的 upload client 封装，只是简单的顺序调用接口，没有异常的处理。直到有一天，一个用户说我要上传一个 11 TB 的单文件到对象存储 (狗头.png)

为了将分块上传的逻辑与我们刚才的逻辑可以优雅的结合起来，原来的 Object 和 Job （也就是一个 Folder）被组合并拆分成了三种 Object：DirectoryObject，SingleObject，PartialObject。顾名思义，DirectoryObject 就等同于原来的 Job，SingleObject 表示一个完整的 Object，而 PartialObject 除了有跟 SingleObject 一样的属性之外，它还会携带着与分段上传有关的信息，比如 part number，upload id 等。这样就使得每一个 PartialObject 都可以独立的进行上传，不需要依赖外部的信息。

分段上传在实现的过程中最大限度的复用了原有的逻辑，只不过在每一个 Object 开始上传时会做相关的检查：

- 如果是 PartialObject，则会使用 Object 中的信息进行分段上传。
- 如果是 SingleObject，则会根据 Endpoint 是否支持分段和这个 Object 的大小来判断是否需要拆分成 PartialObject：
  - 如果 Endpoint 不支持分段，或者 Object 的大小不够大，则会直接上传。
  - 反之，则会使用 Endpoint 的初始化分段接口进行分片，并将所有的 PartialObject 创建好。

## 实现

刚才我们讲了 qscamel 几处关键部分的设计，下面我们聊一聊 qscamel 的实现。qscamel 在实现过程中保持着对开发者友好的风格，没有使用什么黑科技，也没有使用什么奇怪的 Hack，简单直接，使用的也都是最常见的模型。

### 生产者-消费者

在绝大部分场景下，列取操作都要比上传和下载操作来得快，因此使用单生产者多消费者的模型更加合适，同时逻辑也会变得更加清晰。实现上我们使用 `sync.WaitGroup` 做了一个简单的 `goroutine` 池，在初始化的时候会一次性创建完毕，并始终监听 Object Channel，在 channel 关闭后自动退出。

### Endpoint 中的 interface

qscamel 要求支持的 endpoint 类型很多，从本地文件系统到各种对象存储，还包括本地文件的列表和 URL 的列表。想要快速开发，便于维护就要求将各个 endpoint 中的公共部分尽可能抽象出来，让 endpoint 实现者只需要关注自己逻辑相关的部分。为了做到这一点，qscamel 将 endpoint 中需要用到的所有方法拆分成了三个 interface，endpoint 实现者可以自行实现自己想要支持的功能。

其中，所有 endpoint 都必须要实现的 base interface 中包括如下函数：

```go
// Base is the interface that both Source and Destination should implement.
type Base interface {
	// Name will return the endpoint's name.
	Name(ctx context.Context) (name string)

	// Stat will get the metadata.
	Stat(ctx context.Context, p string) (o *model.SingleObject, err error)

	// Read will return a reader.
	Read(ctx context.Context, p string) (r io.Reader, err error)
	// ReadRange will read content with range [offset, offset+size)
	ReadRange(ctx context.Context, p string, offset, size int64) (r io.Reader, err error)
}
```

如果想要作为 Source，则还需要 Source interface：

```go
// Source is the interface for source endpoint.
type Source interface {
	Base

	// List will list from the job.
	List(ctx context.Context, j *model.DirectoryObject, fn func(model.Object)) (err error)

	// Reach will return an accessible url.
	Reach(ctx context.Context, p string) (url string, err error)
	// Reachable will return whether current endpoint supports reach.
	Reachable() bool
}
```

其中 List 会用来支持列取，而 Reach 则是可选的，这主要是用来支持对象存储的 Object Fetch 功能。

如果想要作为一个 Task 的 Destination，则需要实现 Destination interface：

```go
// Destination is the interface for destination endpoint.
type Destination interface {
	Base

	// Delete will use endpoint to delete the path.
	Delete(ctx context.Context, p string) (err error)
	// Deletable will return whether current endpoint supports delete.
	Deletable() bool

	// Fetch will use endpoint to fetch the url.
	Fetch(ctx context.Context, path, url string) (err error)
	// Fetchable will return whether current endpoint supports fetch.
	Fetchable() bool

	// InitPart will inti a multipart upload.
	InitPart(ctx context.Context, p string, size int64) (uploadID string, partSize int64, partNumbers int, err error)
	// UploadPart will upload a part.
	UploadPart(ctx context.Context, o *model.PartialObject, r io.Reader) (err error)
	// Partable will return whether current endpoint supports multipart upload.
	Partable() bool

	// Write will read data from the reader and write to endpoint.
	Write(ctx context.Context, path string, size int64, r io.Reader) (err error)
	// Writable will return whether current endpoint supports write.
	Writable() bool
}
```

在每个 interface 中，开发者对自己不想或者暂时不想实现的功能都可以在对应的 `Xxxable()` 函数中返回 `false` 即可，qscamel 在初始化任务时会进行对应功能的检查，并在任务要求不满足时报错。

这样，我们 qscamel 就能够方便快捷的扩展新 endpoint 了~

### LevelDB

qscamel 是我们 QingStor Team 推出的第一款有状态的命令行工具，之前我们做 `qingcloud-cli` 和 `qsctl` 都只是直接调用对象存储的 API，不会在本地存储持久化的状态。但是 qscamel 作为一款数据迁移工具，它必须在本地维护大量信息以支持任务的断点续传。

qscamel 在选型过程中考察了很多方案：

- 首先排除掉了所有 Server - Client 模式的数据库，迁移工具要求部署简单，轻量级，如果迁移数据还需要部署一个 MySQL 或者 Redis，那就太滑稽了，因此可选择的一定是嵌入式 DB。
- 然后因为开发者（没错，就是我）的个人偏好，排除掉了所有必须使用 CGO 的嵌入式 DB。RocksDB 非常酷炫，但是因为找不到一个足够好的纯 go 实现，所以被否决了。
- 再次因为 qscamel 规划当中会在 DB 中存储的数据类型不会超过 3 种，同时也不会存在需要 Join 的情况，所以排除掉了所有嵌入式 SQL 数据库。
- 最后在社区那么多嵌入式 K-V 数据库中，我们还需要排除掉所有不靠谱的，没有生产环境实际验证过的，维护状态不佳的，以及看着就不大行的项目。

在筛过好几轮之后，摆在我们面前的可选方案有三个：

- [BoltDB](https://github.com/etcd-io/bbolt) *原作者已经不维护了，现在由 coreos team 的人 Fork 并维护了一份，最近转移给了 etcd-io*
- [Badger](https://github.com/dgraph-io/badger)
- [LevelDB](https://github.com/syndtr/goleveldb)

BoltDB 使用了 B+tree，LevelDB 使用了 LSM tree，而 Badger 则是借鉴了论文 [WiscKey](https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf)，论文我没有细看，但大致的思想是将 LSM trees 中的 Key 和 Value 分开，将 Key 存储在 LSM tree 中，而 Value 则存在 value logs 里面。相对的来说，BoltDB 更加适合于读多写少的场景，而基于 LSM tree 的 DB 写入会更有优势。此外，LevelDB 不提供事务，它提供批量写入和读取时的 Snapshot，而 BoltDB 和 Badger 提供了完整的 ACID 事务，其中 BoltDB 不支持并发写事务，而 Badger 则支持。再三权衡之后，我首先放弃了 Badger。虽然特性很多，功能很强，Benchmark 也非常好看，但是它的特性我们基本上都用不到，加上我个人对这个项目的代码还不是很熟悉，可靠性上还有着疑虑，所以放弃了。

本着够用就行的想法，我一开始选择了被广泛运用的 BoltDB 。但是事实证明这个选择是错误的，在 qscamel 实际的场景下，剧烈的写事务竞争导致性能很差，并且发现 qscamel 对事务其实并没有什么需求，因此切换成了 LevelDB。

## 故事

### 遇事不决，黄金切割

在 qscamel 探索的过程中，有过需要 magic number 的阶段，处于个人偏好，我无一例外的全部选择了黄金切割比。

案例一：生产者与消费者比例

之前 qscamel 是采用的多生产者，多消费者的方案，每个 worker 从一个统一的任务队列中取任务，又是生产者，又是消费者。看起来很美好，但是运行到某个时点，qscamel 总是会停止响应。当然了，现在回头来看可以知道这个 BUG 是由多种原因导致的。但是当时的一个分析是 Worker 的调度有问题，有可能所有的 Worker 都在生产，没有消费，导致整个任务队列阻塞了。作为一个解决方案，需要人为的固定生产者和消费者的比例，纠结了一会儿，选择了 0.618。

事后的测试中发现这个 Fix 完全没有什么用，于是删掉了（

案例二：乱搞的文件一致性检验

为了加快一致性检验的速度，qscamel 曾经自己乱搞过一个[一致性的算法](https://github.com/yunify/qscamel/commit/5a29fc9346b56b6ab5c6377f58d49675ace49838#diff-77889babdacd806bb9d5b8299a56e9a9)。想法非常简单，从文件的头尾和 0.618 处，分别取 3 MB，总计 9 MB，然后计算它们的 MD5 。很快这个想法被毙了，用户开 MD5 的检查就是为了保证自己文件上传没错，搞一个所谓 quickMD5 完全没有实际的意义，要是万一有一个文件 MD5 不对，结果没有检查出来，那就大发了。

总的来说，所有引入黄金切割的尝试全都失败了，但是我还在期待着下一个机会（

### Buffer 的 Bytes

qscamel 很多地方都使用了我朋友 [@Aspire](https://pjw.io/) 写的[库](https://github.com/pengsrc/go-shared)，但是有一天被坑了一手，因为我发现它的 `buffer.Bytes()` 不是线程安全的。因为它是这样实现的：

```go
// Bytes returns a mutable reference to the underlying byte slice.
func (b *BytesBuffer) Bytes() []byte {
	return b.bs
}
```

他将底层的 byte slice 直接返回，那就有可能在使用到一半的时候这个 buffer 被释放并写入了新的值，从而导致外部的调用者看到了一个错误的值。我提了一个 [PR](https://github.com/pengsrc/go-shared/pull/3)，跟 @Aspire 讨论了一下这个问题。虽说当初他实现的时候没有怎么考虑这个问题，但是想了一下他认为这是设计预期的，主要的点有两个：第一，设计这个 buffer 库就是为了复用内存，减少频繁创建 bytes slice 带来的开销，降低 gc 的压力，如果这个地方按照我的 PR 那样返回了一个新的 bytes slice 的话，那这个库就跟它的设计目标相违背了；第二，在 Golang 中，如果没有明确声明并发访问某事物是安全的，那它就不是安全的，比如 Golang 自己 [Buffer 实现](https://golang.org/src/bytes/buffer.go)就不是并发安全的：

```go
// Bytes returns a slice of length b.Len() holding the unread portion of the buffer.
// The slice is valid for use only until the next buffer modification (that is,
// only until the next call to a method like Read, Write, Reset, or Truncate).
// The slice aliases the buffer content at least until the next buffer modification,
// so immediate changes to the slice will affect the result of future reads.
func (b *Buffer) Bytes() []byte { return b.buf[b.off:] }
```

最后的决定是增加一个类似于 `SafeBytes()` 的函数，不过因为懒，所以一直没有做，以后再补上吧~

### 小人物的重构，从早到晚

> 语出猫腻《间客》许乐在老虎死后跟随舰队穿越虫洞，手刃卡顿郡王前：“大人物报仇，隐忍十年也不算晚，小人物的复仇，却是从早到晚。”

其实 qscamel 的分段上传逻辑写了两遍，最开始是在原来的基础上缝缝补补，为 Object 加了很多新的属性，然后加了很多复杂判断，基本可用之后交付给了售前去做测试。晚上下班回家之后实在不满意那个版本，于是采用新的，也就是现在这样的逻辑重新实现了一遍。性能上有轻微提升，逻辑上变得更加顺畅，更主要的是我更加开心了  ʅ(‾◡◝)ʃ 

## 动态

- 这文章写了好几个月了，都不知道动态该写啥了。。
- LOL 洲际赛夺冠了，亚运会也夺冠了，又又又是最有希望的一年，希望今年能拿到 S 系列赛的冠军
- 最近在重温《希灵帝国》，还买了微信读书新出的无限卡，每个月可以免费解锁 300 个章节，按照每个章节 0.3 元的均价，每月 19 块还是比较划算的（会计小能手
- PS 会免了命运 2，跟小伙伴一起突突突了两天，导致接下来的一个星期睡觉都满脑子枪声


## 广告

> 广告位招租，8 点 17 分发

想要加入我们一起来做靠谱的产品吗，快访问 https://www.qingcloud.com/jobs 寻找自己中意的岗位并且给我发简历吧~

