# Project Lamdu

This project aims to create a "next-generation", "live programming" environment that radically improves the programming experience.

See the [Main Page](http://peaker.github.io/lamdu/)


## Installation

#### osx

with [stack](https://github.com/commercialhaskell/stack/releases), [brew](http://brew.sh/) and [git](https://git-scm.com/):

```shell
brew install ftgl leveldb
git clone --recursive https://github.com/Peaker/lamdu
cd lamdu
stack setup
stack install
```

#### ubuntu

with [stack](https://github.com/commercialhaskell/stack/releases) and [git](https://git-scm.com/):
```shell
sudo apt-get update
sudo apt-get install libftgl-dev libleveldb-dev -y
sudo apt-get install libglfw-dev libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev -y
git clone --recursive https://github.com/Peaker/lamdu
cd lamdu
stack setup
stack install
```
