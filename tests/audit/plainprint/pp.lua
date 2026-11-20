function main()
  while true do
    ioports.gpu.clear(0xFF000040)
    print(20, 30, "HELLO WORLD")
    print(20, 60, 1234)
    ioports.gpu.sync()
  end
end
