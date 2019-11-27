
function intersect(M, N) {
    N = N.slice();  // clone array to prevent original array update
    N.sort((a, b) => a > b ? 1 : b > a ? -1 : 0); // sort cloned array

    M = M.slice(); // clone array to prevent original array update
    M.sort((a, b) => a > b ? 1 : b > a ? -1 : 0); // sort cloned array

    let R = [], i = 0, j = 0;

    // compute arrays intersection taking in account the arrays are sorted
    while (i < M.length && j < N.length) {
        if (M[i] === N[j]) {
            R.push(M[i]);
            i++;
            j++;
        } else if (M[i] > N[j]) {
            j++;
        } else {
            i++;
        }
    }


    HTMLCanvas

    return R;
}
