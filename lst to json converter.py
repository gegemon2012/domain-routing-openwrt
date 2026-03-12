import json

with open("./ipsum.lst") as input_file:
    with open("./ipsum_lst.json", "w") as output_file:
        json.dump(
            [{"hostname": line.strip()} for line in input_file.readlines()],
            output_file,
            indent=2,
        )