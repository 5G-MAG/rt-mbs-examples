const fs = require('fs');
const path = require('path')

class Utils {

    static writeToDisk(filepath, content) {
        return new Promise((resolve, reject) => {
            fs.mkdirSync(path.dirname(filepath), { recursive: true });
            fs.writeFile(filepath, content, (err) => {
                if (err) {
                    reject(err)
                } else {
                    resolve()
                }
            })
        })
    }
}

module.exports = Utils
