int func2(void)
{
}

int func1(void)
{
	func2();
	func2();
}

int main(void)
{
	func1();
	func1();

	return 0;
}
