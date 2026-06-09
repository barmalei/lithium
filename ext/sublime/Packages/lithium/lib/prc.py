import subprocess, threading, traceback, io

class PipedPrc:
    def __init__(self, command: str, as_async:bool = True):
        if command is None:
            raise ValueError('Command is empty')
        self.command = command
        self.as_async = as_async

    def exec(self, output_handler = None, error_handler = None):
        process = subprocess.Popen( #
            self.command,
            shell  = True,
            stdin  = subprocess.PIPE,
            stdout = subprocess.PIPE,
            stderr = subprocess.STDOUT,
            universal_newlines = False,
            bufsize = 1
        )

        if self.as_async is True:
            def WRITES(process, output_handler, error_handler):
                try:
                    for line in io.TextIOWrapper(process.stdout, encoding = 'utf-8', errors='strict'):
                        if output_handler is not None:
                            output_handler(process, line)

                    # outs, errs = process.communicate()
                    # for line in outs.split("\n"):
                    #     if output_handler is not None:
                    #         output_handler(process, line + "\n")

                    # if errs is not None:
                    #     print(">>>>> Step 2.1")
                    #     for line in errs.split("\n"):
                    #         if output_handler is not None:
                    #             output_handler(process, line + "\n")


                    # tell the last line has been handled
                    process.stdout.close()
                    if output_handler is not None:
                        output_handler(process, None)
                except Exception as ex:
                    traceback.print_exception(ex)
                    if error_handler is not None:
                        error_handler(self.command, ex)

            std_out = threading.Thread(
                target = WRITES,
                args   = (process, output_handler, error_handler)
            ).start()

            std_err = threading.Thread(
                target = WRITES,
                args   = (process, output_handler, error_handler)
            ).start()
        else:
            while True:
                data = process.stdout.read().decode('utf-8')
                try:
                    if output_handler is not None:
                        for line in data.split("\n"):
                            output_handler(process, line)

                    if process.poll() is not None:
                        # notify the process has been completed
                        if output_handler is not None:
                            output_handler(process, None)
                        break
                except Exception as ex:
                    traceback.print_exc()
                    try:
                        if error_handler is not None:
                            error_handler(self.command, ex)
                    except Exception as ex2:
                        traceback.print_exception(ex2)
                    break

        return process

