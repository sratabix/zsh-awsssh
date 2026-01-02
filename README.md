# zsh-awsssh

> A Zsh plugin to List, Select and SSH into an EC2 instance!

<img width="1424" alt="image" src="https://github.com/raisedadead/zsh-awsssh/assets/1884376/faf14758-7e76-4759-8c25-2cb39605a217">

Originally by Mrugesh Mohapatra, Modified by sratabix.

## Installation

Requires [fzf](https://github.com/junegunn/fzf)

### Zplug

```zsh
zplug "sratabix/zsh-awsssh"
```

### Antigen

```zsh
antigen bundle sratabix/zsh-awsssh
```

### Oh-My-Zsh

```zsh
git clone https://github.com/sratabix/zsh-awsssh.git $ZSH_CUSTOM/plugins/zsh-awsssh
```

```zsh
plugins=(
  #...
  zsh-awsssh
  )
```

### Manual

```zsh
git clone https://github.com/sratabix/zsh-awsssh.git
source zsh-awsssh/awsssh.plugin.zsh
```

## Usage

```zsh
awsssh --help
```

## License

Software: The software as it is licensed under the [ISC](LICENSE) License,
please feel free to extend, re-use, share the code.
