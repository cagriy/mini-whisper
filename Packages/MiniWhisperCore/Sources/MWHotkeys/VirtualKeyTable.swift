/// macOS virtual key code ↔ character mapping, verbatim from `hotkey.py:19-30`.
/// Stable across macOS versions (unchanged since the Carbon API).
public enum VirtualKeyTable {
    static let vkToCharacter: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`",
    ]

    static let characterToVK: [Character: UInt16] = Dictionary(
        uniqueKeysWithValues: vkToCharacter.map { ($0.value, $0.key) }
    )

    public static func character(for vk: UInt16) -> Character? { vkToCharacter[vk] }

    public static func virtualKey(for character: Character) -> UInt16? { characterToVK[character] }
}
