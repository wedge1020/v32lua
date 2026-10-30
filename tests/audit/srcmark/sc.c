
int add(int a, int b)
{
    int c = a * b;
    return c + 1;
}
void main(void)
{
    int s = 0;
    for (int i = 0; i < 10; i++)
        s = s + add(i, 3);
    asm
    {
        "mov R0, R0"
    }
    s = s + 1;
}
