# zsh-awsssh

> A Zsh plugin to List, Select and SSH into an EC2 instance!

<img width="1424" alt="image" src="https://github.com/raisedadead/zsh-awsssh/assets/1884376/faf14758-7e76-4759-8c25-2cb39605a217">

Originally by Mrugesh Mohapatra, Modified by sratabix.

## Installation

Requires [fzf](https://github.com/junegunn/fzf) and the AWS Session Manager plugin.

### AWS Session Manager plugin (macOS)

```zsh
brew install --cask session-manager-plugin
```

For other platforms, see the [AWS docs](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

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

## Usage

```zsh
awsssh --help
```

## License

Software: The software as it is licensed under the [ISC](LICENSE) License,
please feel free to extend, re-use, share the code.
