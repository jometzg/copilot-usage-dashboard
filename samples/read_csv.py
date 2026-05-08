import argparse
import csv
from pathlib import Path


def read_csv_and_echo(csv_path: Path) -> None:
    if not csv_path.exists():
        raise FileNotFoundError(f"CSV file not found: {csv_path}")

    with csv_path.open("r", newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)

        if reader.fieldnames:
            print("Header:", ", ".join(reader.fieldnames))
        else:
            print("No header found.")

        print("Rows:")
        for index, row in enumerate(reader, start=1):
            print(f"{index}: {row}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Read a CSV file and echo rows to the console.")
    parser.add_argument(
        "csv_path",
        nargs="?",
        default="samples/generic.csv",
        help="Path to the CSV file (default: samples/generic.csv)",
    )

    args = parser.parse_args()
    read_csv_and_echo(Path(args.csv_path))


if __name__ == "__main__":
    main()
