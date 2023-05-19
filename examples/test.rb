require 'pathname'

class A

    def a()
        self.instance_exec(&@b)
        return 1,1
    end

    def b
        m1, m2 = a()
    end


end