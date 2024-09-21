import { createSlice } from "@reduxjs/toolkit";
import { globalStates as gs } from './states/globalStates'
import { globalActions as ga } from './actions/globalActions'

export const globalSlices = createSlice({
    name: 'global',
    initialState: gs,
    reducers: ga
})

export const globalActions = globalSlices.actions
export default globalSlices.reducer