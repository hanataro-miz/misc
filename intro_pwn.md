# pwn intro
```c
1 #include <string.h>
2 #include <stdio.h>
3
4 int main(int argc, char *argv[]) 
5 {
6   char str1[] = "def"; 
7   char str2[] = "abc"; 
8
9   int ret = strcmp(str1, str2); 
10  printf("%d", ret); 
11
12  return ret; 
13 }
```
