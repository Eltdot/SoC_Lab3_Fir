import numpy as np

def read_input_file(filename):

    with open(filename, 'r') as file:
        data = [float(line.strip()) for line in file.readlines()]
    return data

def fir_filter(input_data, coefficients, tape_num=11, output_length=None):
    """x[i]*coef[0] + x[i-1]*coef[1] + ... + x[i-10]*coef[10]"""
    assert len(coefficients) == tape_num, "should same as tape_num"
    
    output_length = output_length or len(input_data)
    output_data = []
    

    for i in range(output_length):
        value = sum(coefficients[j] * (input_data[i - j] if (i - j) >= 0 else 0) for j in range(tape_num))
        output_data.append(int(round(value)))
    return output_data


def write_output_file(filename, data):
    with open(filename, 'w') as file:
        for value in data:
            file.write(f"{value:.0f}\n")

def main():
    x_filename = r"D:\Verilog-porgram\SoC_Lab\Lab3\py\x.dat"
    coef_filename = r"D:\Verilog-porgram\SoC_Lab\Lab3\py\coef.dat" 
    output_filename = r"D:\Verilog-porgram\SoC_Lab\Lab3\py\y.dat"
    
    input_data = read_input_file(x_filename)
    
    coefficients = read_input_file(coef_filename)
    
    output_data = fir_filter(input_data, coefficients, tape_num=32, output_length=len(input_data))
    
    write_output_file(output_filename, output_data)
    
    print(f"write the golden data in {output_filename}")

if __name__ == "__main__":
    main()