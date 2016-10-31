struct {
	struct inner {
		int a;
		int b;
	} inner1;
	struct inner inner2;
	int c;
} astruct = {0};

int main(void)
{
	astruct.c = 20;
}
