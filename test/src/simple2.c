#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

int main(void)
{
	void *handle;
	void (*func3)(void);
	handle = dlopen("./func3.so", RTLD_LAZY);
	if (!handle)
	{
		fprintf(stderr, "%s\n", dlerror());
		exit(EXIT_FAILURE);
	}

	*(void **)(&func3) = dlsym(handle, "func3");
	(*func3)();
	dlclose(handle);
	exit(EXIT_SUCCESS);
	return 0;
}
