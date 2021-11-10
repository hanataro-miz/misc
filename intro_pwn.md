# pwn intro
## ソースコード : intro.c
```c
#include <string.h>
#include <stdio.h>

int main(int argc, char *argv[]) 
{
  char str1[] = "def"; 
  char str2[] = "abc"; 

  int ret = strcmp(str1, str2); 
  printf("%d", ret); 

  return ret; 
}
```


## Pwnとは？
PwnableとはCTFのジャンルの1つで、プログラムの脆弱性をつき、本来アクセスできないメモリ領域にアクセスして操作し、フラグを取得する感じの問題です。
別名としてExploitがあります。[1]

### 今回やること
- スタックに慣れる
- gdbの使い方をなんとなく覚えておく
intro.cの解析を通してこれを行っていきます。
## intro.cの解析
intro.cをコンパイルして、gdbで解析していきます。
```
gcc -m32 intro.c -o intro -fno-stack-protector -no-pie
```

