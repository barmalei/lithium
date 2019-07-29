        const { exec     }  = require('child_process');
        const { execSync }  = require('child_process');
        const { spawn }  = require('child_process');

//      let pr = spawn('ruby', [ '/Users/brigadir/projects/.lithium/project.rb' ]);
//      let pr = spawn('ruby', [ '/Users/brigadir/projects/.lithium/project.rb' ]);
//      let pr = spawn('ls', ['-lh', '/usr']);

//        let pr = exec('ruby "/Users/brigadir/projects/.lithium/lib/lithium.rb"', (err, stdout, stderr) => {
        let child = spawn('ruby', ['--help'])

        // , (err, stdout, stderr) => {
        //     if(err || stderr) {
        //         console.log(stdout);
        //         console.log(err || stderr);
        //         return;
        //     }

        //     console.log(stdout);
        // });


        child.stdout.on('data', (data) => {
            console.log(`child stdout:\n${data}`);
        });

        child.stderr.on('data', (data) => {
            console.error(`child stderr:\n${data}`);
        });

        //let pr = execSync('ruby "/Users/brigadir/projects/.lithium/lib/lithium.rb"')
        //let pr = execSync('ruby --help')


        //console.log(pr)
