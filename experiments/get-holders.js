const fs = require("fs");
const request = require("request");
const util = require("util");
const cheerio = require("cheerio");

const TOKEN_ADDRESS = "0x4728a6790ba272448094c94ee11e203b79a5e012";

const holders = [];

const getHolderUrl = async () => {
  const etherHolderUrl = `https://etherscan.io/token/generic-tokenholders2?a=${TOKEN_ADDRESS}&sid=&m=normall&s=0&p=`;

  const requestPromise = util.promisify(request);

  const { body } = await requestPromise(`${etherHolderUrl}1`);

  const $doc = cheerio.load(body);

  const totalPage = $doc("#maintable div nav li strong").eq(1);

  const lastPage = parseInt(totalPage.text());
  console.log("total page", lastPage);

  for (let i = 1; i <= lastPage; i++) {
    const { body } = await requestPromise(`${etherHolderUrl}${i}`);

    const $doc = cheerio.load(body);

    const trs = $doc(".table tbody tr");
    trs.each((i, elem) => {
      const row = $doc(elem);
      let address = row
        .find("td")
        .eq(1)
        .text()
        .toLocaleLowerCase();

      if (!address.startsWith("0x")) {
        const text = row
          .find("td")
          .eq(1)
          .find("span a")
          .attr("href");

        const index = text.indexOf("a=");
        address = text.substring(index + 2, index + 44);
      }

      holders.push(address);
    });

    console.log("finish page", i);
  }

  await outPutAddressToFile();
};

const outPutAddressToFile = async () => {
  const fileStream = fs.createWriteStream("holder.txt", {
    flags: "w"
  });

  for (const holder of holders) {
    fileStream.write(`${holder}\n`);
  }

  fileStream.end();
};

getHolderUrl();
