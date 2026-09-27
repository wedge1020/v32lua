-- rgba() takes 3 or 4 arguments: this must not compile
function main()
    ioports.gpu.multiply = rgba(1, 2, 3, 4, 5)
end
