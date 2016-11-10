int func2(int b1, int b2)
{
}

int func1(int a)
{
	func2(a + 1, 1);
	func2(a + 1, 2);
}

int spin;

int main(void)
{
	func1(1);
	func1(2);

	while (spin)
		;

	return 0;
}
